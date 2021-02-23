/**
   Synth2 virtual analog syntesizer.

   Copyright: klknn 2021.
   Copyright: Elias Batek 2018.
   License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module synth2.client;

import std.algorithm.comparison : clamp;
import std.traits : EnumMembers;

import dplug.core.nogc : destroyFree, mallocNew;
import dplug.core.vec : makeVec, Vec;
import dplug.client.client : Client, LegalIO, parsePluginInfo, PluginInfo, TimeInfo;
import dplug.client.graphics : IGraphics;
import dplug.client.dllmain : DLLEntryPoint, pluginEntryPoints;
import dplug.client.params : Parameter;
import dplug.client.midi : MidiMessage, makeMidiMessageNoteOn;
import mir.math : exp2, log, sqrt, PI;

import synth2.filter : Filter, FilterKind, filterNames;
import synth2.gui : Synth2GUI;
import synth2.oscillator : Oscillator, Waveform, waveformNames;
import synth2.params : Params, ParamBuilder, paramNames;

version (unittest) {} else {
// This define entry points for plugin formats,
// depending on which version identifiers are defined.
mixin(pluginEntryPoints!Synth2Client);
}

/// Polyphonic digital-aliasing synth
class Synth2Client : Client {
 public:
  nothrow @nogc:

  // NOTE: this method will not call until GUI required (lazy)
  override IGraphics createGraphics() {
    _gui = mallocNew!Synth2GUI(
        this.param(Params.osc1Waveform),
    );
    return _gui;
  }

  override PluginInfo buildPluginInfo() {
    // Plugin info is parsed from plugin.json here at compile time.
    static immutable info = parsePluginInfo(import("plugin.json"));
    return info;
  }

  override Parameter[] buildParameters() {
    return ParamBuilder.buildParameters();
  }

  override LegalIO[] buildLegalIO() {
    auto io = makeVec!LegalIO();
    io ~= LegalIO(0, 1);
    io ~= LegalIO(0, 2);
    return io.releaseData();
  }

  override int maxFramesInProcess() pure {
    return 32; // samples only processed by a maximum of 32 samples
  }

  override void reset(double sampleRate, int maxFrames,
                      int numInputs, int numOutputs) {
    foreach (ref o; this._osc1s) {
      o.setSampleRate(sampleRate);
    }
    this._osc2.setSampleRate(sampleRate);
    this._oscSub.setSampleRate(sampleRate);
    this._filter.setSampleRate(sampleRate);
  }

  override void processAudio(const(float*)[] inputs, float*[] outputs,
                             int frames, TimeInfo info) {
    // TODO: use info.timeInSamples to set the RNG status.

    const ampGain = exp2(readParam!float(Params.ampGain));
    if (ampGain == 0) return;  // no output

    const oscMix = readParam!float(Params.oscMix);
    const sync = readParam!bool(Params.osc2Sync);
    const ring = readParam!bool(Params.osc2Ring);
    const fm = readParam!float(Params.osc1FM);
    const doFM = !sync && !ring && fm > 0;

    const attack = readParam!float(Params.ampAttack) - ParamBuilder.logBias;
    const decay = readParam!float(Params.ampDecay) - ParamBuilder.logBias;
    const sustain = exp2(readParam!float(Params.ampSustain));
    const release = readParam!float(Params.ampRelease) - ParamBuilder.logBias;

    const oscKeyShift = readParam!int(Params.oscKeyShift);
    const oscTune = readParam!float(Params.oscTune);
    const oscPhase = readParam!float(Params.oscPhase);
    const pw = readParam!float(Params.oscPulseWidth);
    const vel = readParam!float(Params.ampVel);

    const useOsc1 = oscMix != 1 || sync || ring || fm > 0;
    const osc1Det = readParam!float(Params.osc1Det);
    if (useOsc1) {
      foreach (i, ref _osc1; _osc1s) {
        _osc1.setWaveform(readParam!Waveform(Params.osc1Waveform));
        _osc1.setPulseWidth(pw);
        _osc1.setVelocitySense(vel);
        _osc1.setADSR(attack, decay, sustain, release);
        _osc1.setNoteDiff(oscKeyShift + oscTune);
        if (oscPhase != ParamBuilder.ignoreOscPhase) {
          _osc1.setInitialPhase(oscPhase);
        }
        if (osc1Det == 0) break; // skip detuned osc1s
        _osc1.setNoteDetune(log(osc1Det + 1f) * 2 *
                            log(i + 1f) / log(cast(float) _osc1s.length));
      }
    }

    const useOsc2 = oscMix != 0 || sync || ring || fm > 0;
    if (useOsc2) {
      _osc2.setWaveform(readParam!Waveform(Params.osc2Waveform));
      _osc2.setPulseWidth(pw);
      _osc2.setNoteTrack(readParam!bool(Params.osc2Track));
      _osc2.setNoteDiff(
          oscKeyShift + oscTune +
          readParam!int(Params.osc2Pitch) + readParam!float(Params.osc2Fine));
      _osc2.setVelocitySense(vel);
      _osc2.setADSR(attack, decay, sustain, release);
      if (oscPhase != ParamBuilder.ignoreOscPhase) {
        _osc2.setInitialPhase(oscPhase);
      }
    }

    const oscSubVol = exp2(readParam!float(Params.oscSubVol));
    if (oscSubVol != 0) {
      _oscSub.setWaveform(readParam!Waveform(Params.oscSubWaveform));
      _oscSub.setNoteDiff(
          oscKeyShift + oscTune + readParam!bool(Params.oscSubOct) ? -12 : 0);
      _oscSub.setVelocitySense(vel);
      _oscSub.setADSR(attack, decay, sustain, release);
      if (oscPhase != ParamBuilder.ignoreOscPhase) {
        _oscSub.setInitialPhase(oscPhase);
      }
    }

    // Setup freq by MIDI and params.
    foreach (msg; this.getNextMidiMessages(frames)) {
      if (useOsc1) {
        foreach (ref o1; _osc1s) {
          o1.setMidi(msg);
          if (osc1Det == 0) break;
        }
      }
      if (useOsc2) _osc2.setMidi(msg);
      if (oscSubVol != 0) _oscSub.setMidi(msg);
    }
    if (useOsc1) {
      foreach (ref o; _osc1s) {
        o.updateFreq();
        if (osc1Det == 0) break;
      }
    }
    if (useOsc2) _osc2.updateFreq();
    if (oscSubVol != 0) _oscSub.updateFreq();

    _filter.setParams(
        readParam!FilterKind(Params.filterKind),
        readParam!float(Params.filterCutoff),
        readParam!float(Params.filterQ),
    );

    // Generate samples.
    foreach (frame; 0 .. frames) {
      // osc1
      float o1 = 0;
      if (useOsc1) {
        foreach (ref o; _osc1s) {
          if (doFM) {
            o.setFM(fm, _osc2);
          }
          o1 += o.front;
          o.popFront();
          if (osc1Det == 0) break;
        }
      }
      float output = (1.0 - oscMix) * o1;

      // osc2
      if (useOsc2) {
        if (sync) {
          _osc2.synchronize(_osc1s[0]);
        }
        output += oscMix * _osc2.front * (ring ? o1 : 1f);
        _osc2.popFront();
      }

      // oscSub
      if (oscSubVol != 0) {
        output += oscSubVol * _oscSub.front;
        _oscSub.popFront();
      }
      outputs[0][frame] = ampGain * _filter.apply(output);
    }
    foreach (chan; 1 .. outputs.length) {
      outputs[chan][0 .. frames] = outputs[0][0 .. frames];
    }
  }

 private:
  Filter _filter;
  Oscillator _osc2, _oscSub;
  Oscillator[8] _osc1s;  // +7 for detune
  Synth2GUI _gui;
}


/// Host for running one client for testing.
struct TestHost {
  Synth2Client client;
  int frames = 8;
  Vec!float[2] outputFrames;
  MidiMessage msg1 = makeMidiMessageNoteOn(0, 0, 100, 100);
  MidiMessage msg2 = makeMidiMessageNoteOn(1, 0, 90, 90);

  @nogc nothrow:

  /// Sets param to test.
  void setParam(Params pid, T)(T val) {
    auto p = __traits(getMember, ParamBuilder, paramNames[pid]);
    static if (is(T == Waveform)) {
      double v;
      assert(p.normalizedValueFromString(waveformNames[val], v));
    }
    else static if (is(T == FilterKind)) {
      double v;
      assert(p.normalizedValueFromString(filterNames[val], v));
    }
    else static if (is(T == bool)) {
      auto v = val ? 1.0 : 0.0;
    }
    else static if (is(T == int)) {
      auto v = clamp((cast(double)val - p.minValue) /
                     (p.maxValue - p.minValue), 0.0, 1.0);
    }
    else static if (is(T : double)) {
      auto v = p.toNormalized(val);
    }
    else {
      static assert(false, "unknown param");
    }
    client.param(pid).setFromHost(v);
  }

  void processAudio() {
    outputFrames[0].resize(this.frames);
    outputFrames[1].resize(this.frames);
    client.reset(44100, 32, 0, 2);

    float*[2] inputs, outputs;
    inputs[0] = null;
    inputs[1] = null;
    outputs[0] = &outputFrames[0][0];
    outputs[1] = &outputFrames[1][0];

    client.enqueueMIDIFromHost(msg1);
    client.enqueueMIDIFromHost(msg2);

    TimeInfo info;
    client.processAudio(inputs[], outputs[], frames, info);
  }

  /// Returns true iff the val changes outputs of processAudio.
  bool paramChangeOutputs(Params pid, T)(T val) {
    double origin = this.client.param(pid).getForHost;

    // 1st trial w/o param
    this.processAudio();
    auto prev = makeVec!float(this.frames);
    foreach (i; 0 .. frames) {
      prev[i] = outputFrames[0][i];
    }
    this.setParam!(pid, T)(val);

    // 2nd trial w/ param
    this.processAudio();

    // revert param
    this.client.param(pid).setFromHost(origin);

    foreach (i; 0 .. frames) {
      if (prev[i] != outputFrames[0][i])
        return true;
    }
    return false;
  }
}

/// Test default params with benchmark.
@nogc nothrow @system
unittest {
  import core.stdc.stdio : printf;
  import std.datetime.stopwatch : benchmark;

  TestHost host = { client: mallocNew!Synth2Client(), frames: 100 };
  scope (exit) destroyFree(host.client);

  host.processAudio();  // to omit the first record.
  auto time = benchmark!(() => host.processAudio())(100)[0].split!("msecs", "usecs");
  printf("benchmark (default): %ld ms %ld us\n", time.msecs, time.usecs);
  version (LDC) assert(time.msecs <= 20);
}

/// Test deterministic outputs.
@nogc nothrow @system
unittest {
  enum N = 100;
  float[N] prev;
  TestHost host = { client: mallocNew!Synth2Client(), frames: N };
  scope (exit) destroyFree(host.client);

  // 1st
  host.processAudio();
  prev[] = host.outputFrames[0][];
  bool notNaN = true;
  foreach (x; prev) {
    notNaN &= x != float.init;
  }
  assert(notNaN);

  // 2nd
  host.processAudio();
  assert(prev[] == host.outputFrames[0][]);
}

/// Test changing waveforms.
@nogc nothrow @system
unittest {
  TestHost host = { mallocNew!Synth2Client() };
  scope (exit) destroyFree(host.client);

  host.setParam!(Params.oscMix)(0.5);
  host.setParam!(Params.oscSubVol)(0.5);
  foreach (wf; EnumMembers!Waveform) {
    host.setParam!(Params.osc1Waveform)(wf);
    host.setParam!(Params.osc2Waveform)(wf);
    host.setParam!(Params.oscSubWaveform)(wf);
    host.processAudio();
    assert(host.client._osc1s[0].lastUsedWave.waveform == wf);
    assert(host.client._osc2.lastUsedWave.waveform == wf);
    assert(host.client._oscSub.lastUsedWave.waveform == wf);
  }
}

/// Test FM (TODO: check values).
@nogc nothrow @system
unittest {
  TestHost host = { mallocNew!Synth2Client() };
  scope (exit) destroyFree(host.client);

  assert(host.paramChangeOutputs!(Params.osc1FM)(10.0));
}

/// Test detune.
@nogc nothrow @system
unittest {
  TestHost host = { mallocNew!Synth2Client() };
  scope (exit) destroyFree(host.client);

  assert(host.paramChangeOutputs!(Params.osc1Det)(1.0));

  host.processAudio();
  // Check the detune osc1s are NOT playing.
  foreach (o; host.client._osc1s[1 .. $]) {
    assert(!o.voices[0].isPlaying);
  }

  host.setParam!(Params.osc1Det)(1.0);
  host.processAudio();
  // Check all the osc1s are playing.
  foreach (o; host.client._osc1s) {
    assert(o.voices[0].isPlaying);
  }
}

/// Test oscKeyShift/oscTune/oscPhase.
@nogc nothrow @system
unittest {
  TestHost host = { mallocNew!Synth2Client() };
  scope (exit) destroyFree(host.client);

  foreach (mix; [0.0, 1.0]) {
    host.setParam!(Params.oscMix)(mix);
    assert(host.paramChangeOutputs!(Params.oscKeyShift)(12));
    assert(host.paramChangeOutputs!(Params.oscTune)(0.5));
    assert(host.paramChangeOutputs!(Params.oscPhase)(0.5));
  }
}

/// Test Osc2 Track and pitch
@nogc nothrow @system
unittest {
  TestHost host = { mallocNew!Synth2Client() };
  scope (exit) destroyFree(host.client);

  // Check initial pitch.
  host.setParam!(Params.oscMix)(1.0);
  host.setParam!(Params.osc2Track)(false);
  host.processAudio();
  assert(host.client._osc2.lastUsedWave.freq == 440);

  // Check pitch is 1 octave down.
  host.setParam!(Params.osc2Pitch)(-12);
  host.processAudio();
  assert(host.client._osc2.lastUsedWave.freq == 220);

  // Check pitch is down from 220hz.
  host.setParam!(Params.osc2Fine)(-1.0);
  host.processAudio();
  assert(host.client._osc2.lastUsedWave.freq < 220);
}

/// Test sync.
@nogc nothrow @system
unittest {
  TestHost host = { mallocNew!Synth2Client() };
  scope (exit) destroyFree(host.client);

  host.frames = 100;
  host.setParam!(Params.oscMix)(1.0);
  host.setParam!(Params.osc2Pitch)(-2);
  assert(host.paramChangeOutputs!(Params.osc2Sync)(true));
}

/// Test ring.
@nogc nothrow @system
unittest {
  TestHost host = { mallocNew!Synth2Client() };
  scope (exit) destroyFree(host.client);

  host.setParam!(Params.oscMix)(1.0);
  assert(host.paramChangeOutputs!(Params.osc2Ring)(true));
}

/// Test pulse width.
@nogc nothrow @system
unittest {
  TestHost host = { mallocNew!Synth2Client() };
  scope (exit) destroyFree(host.client);

  // PW does NOT work for Waveform != pulse.
  host.setParam!(Params.osc1Waveform)(Waveform.sine);
  assert(!host.paramChangeOutputs!(Params.oscPulseWidth)(0.1));

  // PW only works for Waveform.pulse.
  host.setParam!(Params.osc1Waveform)(Waveform.pulse);
  assert(host.paramChangeOutputs!(Params.oscPulseWidth)(0.1));
}

/// Test oscSubVol.
@nogc nothrow @system
unittest {
  TestHost host = { mallocNew!Synth2Client() };
  scope (exit) destroyFree(host.client);

  assert(host.paramChangeOutputs!(Params.oscSubVol)(1.0));
}

/// Test ampVel.
@nogc nothrow @system
unittest {
  TestHost host = { mallocNew!Synth2Client() };
  scope (exit) destroyFree(host.client);
  assert(host.paramChangeOutputs!(Params.ampVel)(1.0));
}

/// Test filter
@nogc nothrow @system
unittest {
  TestHost host = { mallocNew!Synth2Client() };
  scope (exit) destroyFree(host.client);
  foreach (fkind; EnumMembers!FilterKind) {
    host.setParam!(Params.filterKind)(fkind);
    assert(host.paramChangeOutputs!(Params.filterCutoff)(50));
    if (fkind != FilterKind.HP6 && fkind != FilterKind.LP6) {
      assert(host.paramChangeOutputs!(Params.filterQ)(50));
    }
  }
}
