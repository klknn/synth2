/**
Synth2 virtual analog syntesizer.

Copyright: klknn 2021.
Copyright: Elias Batek 2018.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module synth2.client;

import std.algorithm.comparison : clamp;
import std.traits : EnumMembers;
import std.math : tanh;

import dplug.core.math : convertDecibelToLinearGain;
import dplug.core.nogc : destroyFree, mallocNew;
import dplug.core.vec : makeVec, Vec;
import dplug.client.client : Client, LegalIO, parsePluginInfo, PluginInfo, TimeInfo;
import dplug.client.graphics : IGraphics;
import dplug.client.params : Parameter;
import dplug.client.midi : MidiMessage, makeMidiMessageNoteOn, makeMidiMessageNoteOff;
import mir.math : exp2, log, sqrt, PI, fastmath;

import synth2.chorus : MultiChorus;
import synth2.delay : Delay, DelayKind;
import synth2.equalizer : Equalizer;
import synth2.effect : EffectKind, MultiEffect;
import synth2.envelope : ADSR;
import synth2.filter : FilterKind;
import synth2.modfilter : ModFilter;
import synth2.lfo : Interval, LFO, Multiplier, toBar, toSeconds;
version (unittest) {} else import synth2.gui : Synth2GUI;
import synth2.oscillator : Oscillator;
import synth2.waveform : Waveform;
import synth2.params : Params, ParamBuilder, paramNames, MEnvDest, LfoDest, VoiceKind;

version (unittest) {} else {
  import dplug.client.dllmain : DLLEntryPoint, pluginEntryPoints;

  // This define entry points for plugin formats,
  // depending on which version identifiers are defined.
  mixin(pluginEntryPoints!Synth2Client);
}

/// Polyphonic digital-aliasing synth
class Synth2Client : Client {
 public:
  nothrow @nogc @fastmath:

  /// ctor.
  this() {
    super();
    _effect = mallocNew!MultiEffect;
  }

  ~this() {
    destroyFree(_effect);
  }

  // NOTE: this method will not call until GUI required (lazy)
  version (unittest) {} else
  override IGraphics createGraphics() {
    _gui = mallocNew!Synth2GUI(
        this.params,
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
    foreach (ref o; _osc1s) {
      o.setSampleRate(sampleRate);
    }
    _osc2.setSampleRate(sampleRate);
    _oscSub.setSampleRate(sampleRate);
    _filter.setSampleRate(sampleRate);
    _menv.setSampleRate(sampleRate);
    _menv.sustainLevel = 0;
    _menv.releaseTime = 0;
    _effect.setSampleRate(sampleRate);
    _delay.setSampleRate(sampleRate);
    _chorus.setSampleRate(sampleRate);
    _eq.setSampleRate(sampleRate);
    foreach (ref lfo; _lfos) {
      lfo.setSampleRate(sampleRate);
    }
  }

  override void processAudio(const(float*)[] inputs, float*[] outputs,
                             int frames, TimeInfo info) {
    // TODO: update tempo by a parameter listener.
    version (unittest) {
    } else {
      if (_gui) {
        _gui.setTempo(info.tempo);
      }
    }

    const poly = readParam!int(Params.voicePoly);
    const voiceKind = readParam!VoiceKind(Params.voiceKind);
    const portament = readParam!float(Params.voicePortament) - ParamBuilder.logBias;
    const autoPortament = readParam!bool(Params.voicePortamentAuto);
    const legato = voiceKind == VoiceKind.legato;
    const maxVoices = voiceKind == VoiceKind.poly ? poly : 1;

    const ampGain = exp2(readParam!float(Params.ampGain));
    if (ampGain == 0) return;  // no output

    // Setup LFOs.
    LfoDest[nLFO] lfoDests;
    float[nLFO] lfoAmounts;
    bool[nLFO] lfoTriggers;
    lfoAmounts[0] = readParam!float(Params.lfo1Amount);
    if (lfoAmounts[0] > 0) {
      lfoDests[0] = readParam!LfoDest(Params.lfo1Dest);
      _lfos[0].setParams(
          readParam!Waveform(Params.lfo1Wave),
          readParam!bool(Params.lfo1Sync),
          readParam!float(Params.lfo1Speed),
          readParam!Multiplier(Params.lfo1Mul), info);
      lfoTriggers[0] = readParam!bool(Params.lfo1Trigger);
    }
    lfoAmounts[1] = readParam!float(Params.lfo2Amount);
    if (lfoAmounts[1] > 0) {
      lfoDests[1] = readParam!LfoDest(Params.lfo2Dest);
      _lfos[1].setParams(
          readParam!Waveform(Params.lfo2Wave),
          readParam!bool(Params.lfo2Sync),
          readParam!float(Params.lfo2Speed),
          readParam!Multiplier(Params.lfo2Mul), info);
      lfoTriggers[1] = readParam!bool(Params.lfo2Trigger);
    }

    // Setup OSCs.
    const oscMix = readParam!float(Params.oscMix);
    const sync = readParam!bool(Params.osc2Sync);
    const ring = readParam!bool(Params.osc2Ring);
    const fm = readParam!float(Params.osc1FM);
    const menvDest = readParam!MEnvDest(Params.menvDest);
    const menvAmount = readParam!float(Params.menvAmount);
    bool lfoDoFM = false;
    foreach (i, dst; lfoDests) {
      lfoDoFM |= (lfoAmounts[i] > 0 && dst == LfoDest.fm);
    }
    const doFM = !sync && !ring && (fm > 0 || (menvAmount != 0 && menvDest == MEnvDest.fm) || lfoDoFM);

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
    const useOsc1Det = osc1Det != 0;
    const useOsc2 = oscMix != 0 || sync || ring || fm > 0;
    const oscSubVol = exp2(readParam!float(Params.oscSubVol));
    const useOscSub = oscSubVol != 0;

    const osc1NoteDiff = oscKeyShift + oscTune;
    if (useOsc1) {
      foreach (i, ref Oscillator _osc1; _osc1s) {
        _osc1.setVoice(maxVoices, legato, portament, autoPortament);
        _osc1.setWaveform(readParam!Waveform(Params.osc1Waveform));
        _osc1.setPulseWidth(pw);
        _osc1.setVelocitySense(vel);
        _osc1.setADSR(attack, decay, sustain, release);
        _osc1.setNoteDiff(osc1NoteDiff);
        if (oscPhase != ParamBuilder.ignoreOscPhase) {
          _osc1.setInitialPhase(oscPhase);
        }
        if (osc1Det == 0) break; // skip detuned osc1s
        _osc1.setNoteDetune(log(osc1Det + 1f) * 2 *
                            log(i + 1f) / log(cast(float) _osc1s.length));
      }
    }

    const osc2NoteDiff = oscKeyShift + oscTune + readParam!int(Params.osc2Pitch)
          + readParam!float(Params.osc2Fine);
    if (useOsc2) {
      _osc2.setVoice(maxVoices, legato, portament, autoPortament);
      _osc2.setWaveform(readParam!Waveform(Params.osc2Waveform));
      _osc2.setPulseWidth(pw);
      _osc2.setNoteTrack(readParam!bool(Params.osc2Track));
      _osc2.setNoteDiff(osc2NoteDiff);
      _osc2.setVelocitySense(vel);
      _osc2.setADSR(attack, decay, sustain, release);
      if (oscPhase != ParamBuilder.ignoreOscPhase) {
        _osc2.setInitialPhase(oscPhase);
      }
    }

    if (oscSubVol != 0) {
      _oscSub.setVoice(maxVoices, legato, portament, autoPortament);
      _oscSub.setWaveform(readParam!Waveform(Params.oscSubWaveform));
      _oscSub.setNoteDiff(
          oscKeyShift + oscTune + readParam!bool(Params.oscSubOct) ? -12 : 0);
      _oscSub.setVelocitySense(vel);
      _oscSub.setADSR(attack, decay, sustain, release);
      if (oscPhase != ParamBuilder.ignoreOscPhase) {
        _oscSub.setInitialPhase(oscPhase);
      }
    }

    // Setup filter.
    _filter.useVelocity = readParam!bool(Params.filterUseVelocity);
    _filter.trackAmount = readParam!float(Params.filterTrack);
    _filter.envAmount = readParam!float(Params.filterEnvAmount);
    if (_filter.envAmount != 0) {
      _filter.envelope.attackTime =
          readParam!float(Params.filterAttack) - ParamBuilder.logBias;
      _filter.envelope.decayTime =
          readParam!float(Params.filterDecay) - ParamBuilder.logBias;
      _filter.envelope.sustainLevel = exp2(readParam!float(Params.filterSustain));
      _filter.envelope.releaseTime =
          readParam!float(Params.filterRelease) - ParamBuilder.logBias;
    }
    _filter.setParams(
        readParam!FilterKind(Params.filterKind),
        readParam!float(Params.filterCutoff),
        readParam!float(Params.filterQ));
    const saturation = readParam!float(Params.saturation);
    const satNorm = tanh(saturation);

    // Setup freq by MIDI and params.
    foreach (msg; this.getNextMidiMessages(frames)) {
      if (useOsc1) {
        foreach (ref o1; _osc1s) {
          o1.setMidi(msg);
          if (!useOsc1Det) break;
        }
      }
      if (useOsc2) _osc2.setMidi(msg);
      if (useOscSub) _oscSub.setMidi(msg);
      _filter.setMidi(msg);
      _menv.setMidi(msg);
      foreach (i; 0 .. nLFO) {
        if (lfoTriggers[i]) _lfos[i].setMidi(msg);
      }
    }

    if (useOsc1) {
      foreach (ref o; _osc1s) {
        o.updateFreq();
        if (!useOsc1Det) break;
      }
    }
    if (useOsc2) _osc2.updateFreq();
    if (useOscSub) _oscSub.updateFreq();

    _menv.attackTime = readParam!float(Params.menvAttack);
    _menv.decayTime = readParam!float(Params.menvDecay);

    // Setup _effect.
    const effectMix = readParam!float(Params.effectMix);
    if (effectMix != 0) {
      _effect.setEffectKind(readParam!EffectKind(Params.effectKind));
      _effect.setParams(readParam!float(Params.effectCtrl1),
                        readParam!float(Params.effectCtrl2));
    }

    _eq.setParams(readParam!float(Params.eqLevel),
                  readParam!float(Params.eqFreq),
                  readParam!float(Params.eqQ),
                  readParam!float(Params.eqTone));
    const eqPan = -readParam!float(Params.eqPan);

    // Setup delay.
    const delayMix = readParam!float(Params.delayMix);
    if (delayMix != 0) {
      const delayInterval = Interval(toBar(readParam!float(Params.delayTime)),
                                     readParam!Multiplier(Params.delayMul));
      _delay.setParams(
          readParam!DelayKind(Params.delayKind),
          toSeconds(delayInterval, info.tempo),
          readParam!float(Params.delaySpread),
          readParam!float(Params.delayFeedback));
    }

    // Setup chorus.
    // TODO: support Params.chorusMulti and width.
    const chorusLevel = convertDecibelToLinearGain(
        readParam!float(Params.chorusLevel));
    const chorusOn = readParam!bool(Params.chorusOn) && chorusLevel > 0;
    if (chorusOn) {
      _chorus.setParams(
          readParam!int(Params.chorusMulti),
          readParam!float(Params.chorusWidth),
          readParam!float(Params.chorusTime),
          readParam!float(Params.chorusFeedback),
          readParam!float(Params.chorusDepth),
          readParam!float(Params.chorusRate));
    }

    // Generate samples.
    foreach (frame; 0 .. frames) {
      float menvVal = menvAmount * _menv.front;
      _menv.popFront();
      float[nLFO] lfoVals;
      foreach (i; 0 .. nLFO) {
        lfoVals[i] = lfoAmounts[i] * _lfos[i].front();
        _lfos[i].popFront();
      }

      // modulation
      float modPW = pw;
      float modFM = fm;
      float modOsc1NoteDiff = osc1NoteDiff;
      float modOsc2NoteDiff = osc2NoteDiff;
      float modAmp = ampGain;
      float modPan = eqPan;
      float modCutoff = 0;
      final switch (menvDest) {
        case MEnvDest.pw: modPW += menvVal; break;
        case MEnvDest.fm: modFM += menvVal; break;
        case MEnvDest.osc2: modOsc2NoteDiff += menvVal; break;
      }
      foreach (i; 0 .. nLFO) {
        final switch (lfoDests[i]) {
          case LfoDest.pw: modPW += lfoVals[i]; break;
          case LfoDest.fm: modFM += lfoVals[i]; break;
          case LfoDest.osc12: modOsc1NoteDiff += lfoVals[i]; goto case LfoDest.osc2;
          case LfoDest.osc2: modOsc2NoteDiff += lfoVals[i]; break;
          case LfoDest.amp: modAmp += lfoVals[i]; break;  // maybe *=?
          case LfoDest.pan: modPan += lfoVals[i]; break;
          case LfoDest.filter: modCutoff += lfoVals[i]; break;
        }
      }

      // osc1
      float o1 = 0;
      if (useOsc1) {
        foreach (ref Oscillator o; _osc1s) {
          if (modPW != pw) o.setPulseWidth(modPW);
          if (doFM) o.setFM(modFM, _osc2);
          if (modOsc1NoteDiff != osc1NoteDiff) {
            o.setNoteDiff(modOsc1NoteDiff);
            o.updateFreq();
          }
          o1 += o.front;
          o.popFront();
          if (osc1Det == 0) break;
        }
      }
      float output = (1.0 - oscMix) * o1;

      // osc2
      if (useOsc2) {
        if (modPW != pw) {
          _osc2.setPulseWidth(modPW);
        }
        if (modOsc2NoteDiff != osc2NoteDiff) {
          _osc2.setNoteDiff(modOsc2NoteDiff);
          _osc2.updateFreq();
        }
        _osc2.setPulseWidth(pw + menvVal);
        if (sync) {
          _osc2.synchronize(_osc1s[0]);
        }
        output += oscMix * _osc2.front * (ring ? o1 : 1f);
        _osc2.popFront();
      }

      // oscSub
      if (useOscSub) {
        if (menvDest == MEnvDest.pw) {
          _oscSub.setPulseWidth(pw + menvVal);
        }
        output += oscSubVol * _oscSub.front;
        _oscSub.popFront();
      }

      if (saturation != 0) {
        output = tanh(saturation * output) / satNorm;
      }

      // filter
      _filter.setCutoffDiff(modCutoff);
      output = _filter.apply(output);
      if (effectMix != 0) {
        output = effectMix * _effect.apply(output) + (1f - effectMix) * output;
      }
      output = _eq.apply(output);

      output *= modAmp;
      outputs[0][frame] = (1 + modPan) * output;
      outputs[1][frame] = (1 - modPan) * output;

      if (chorusOn) {
        const chorusOuts = _chorus.apply(outputs[0][frame], outputs[1][frame]);
        foreach (i; 0 .. outputs.length) {
          outputs[i][frame] += chorusLevel * chorusOuts[i];
        }
      }

      if (delayMix != 0) {
        const delayOuts = _delay.apply(outputs[0][frame], outputs[1][frame]);
        foreach (i; 0 .. outputs.length) {
          outputs[i][frame] = (1 - delayMix) * outputs[i][frame] + delayMix * delayOuts[i];
        }
      }
      _filter.popFront();
      _menv.popFront();
    }
  }

 private:
  enum nLFO = 2;
  MultiChorus _chorus;
  Delay _delay;
  LFO[nLFO] _lfos;
  MultiEffect _effect;
  ModFilter _filter;
  ADSR _menv;
  Equalizer _eq;
  Oscillator _osc2, _oscSub;
  Oscillator[8] _osc1s;  // +7 for detune
  version (unittest) {} else Synth2GUI _gui;
}


/// Mock host for testing Synth2Client.
private struct TestHost {
  Synth2Client client;
  int frames = 8;
  Vec!float[2] outputFrames;
  MidiMessage msg1 = makeMidiMessageNoteOn(0, 0, 100, 100);
  MidiMessage msg2 = makeMidiMessageNoteOn(1, 0, 90, 10);
  MidiMessage msg3 = makeMidiMessageNoteOff(2, 0, 100);
  bool noteOff = false;

  @nogc nothrow:

  /// Sets param to test.
  private void setParam(Params pid, T)(T val) {
    auto p = __traits(getMember, ParamBuilder, paramNames[pid]);
    static if (is(T == enum)) {
      double v;
      v = double.init;  // for d-scanner.
      static immutable names = [__traits(allMembers, T)];
      assert(p.normalizedValueFromString(names[val], v));
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
    client.reset(44_100, 32, 0, 2);

    float*[2] inputs, outputs;
    inputs[0] = null;
    inputs[1] = null;
    outputs[0] = &outputFrames[0][0];
    outputs[1] = &outputFrames[1][0];

    client.enqueueMIDIFromHost(msg1);
    client.enqueueMIDIFromHost(msg2);
    if (noteOff) {
      client.enqueueMIDIFromHost(msg3);
    }

    TimeInfo info;
    info.hostIsPlaying = true;
    client.processAudioFromHost(inputs[], outputs[], frames, info);
  }

  /// Returns true iff the val changes outputs of processAudio.
  bool paramChangeOutputs(Params pid, T)(T val) {
    const double origin = this.client.param(pid).getForHost;

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
  printf("benchmark (default): %d ms %d us\n", cast(int) time.msecs, cast(int) time.usecs);
  version (OSX) {} else {
    version (LDC) assert(time.msecs <= 20);
  }
}

/// Test deterministic outputs.
@nogc nothrow @system
unittest {
  enum N = 100;
  float[N] prev;
  TestHost host = { client: mallocNew!Synth2Client(), frames: N };
  scope (exit) destroyFree(host.client);

  foreach (noteOff; [false, true]) {
    // 1st
    host.noteOff = noteOff;
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
}

/// Test pitch bend.
@nogc nothrow @system
unittest {
  import dplug.client.midi : makeMidiMessagePitchWheel;
  enum N = 100;
  float[N] prev;
  TestHost host = { client: mallocNew!Synth2Client(), frames: N };
  scope (exit) destroyFree(host.client);

  host.processAudio();
  prev[] = host.outputFrames[0][];

  host.client.enqueueMIDIFromHost(makeMidiMessagePitchWheel(
      0, 0, 1));
  host.processAudio();
  assert(prev[] != host.outputFrames[0][]);
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
    assert(!o.isPlaying);
  }

  host.setParam!(Params.osc1Det)(1.0);
  host.processAudio();
  // Check all the osc1s are playing.
  foreach (o; host.client._osc1s) {
    assert(o.isPlaying);
  }
}

/// Test oscKeyShift/oscTune/oscPhase.
@nogc nothrow @system
unittest {
  TestHost host = { mallocNew!Synth2Client() };
  scope (exit) destroyFree(host.client);

  foreach (mix; [0.0, 1.0]) {
    host.setParam!(Params.oscMix)(mix);
    host.setParam!(Params.oscSubVol)(1.0);
    assert(host.paramChangeOutputs!(Params.oscKeyShift)(12));
    assert(host.paramChangeOutputs!(Params.oscTune)(0.5));
    assert(host.paramChangeOutputs!(Params.oscPhase)(0.5));
  }
}

/// Test Osc2 Track and pitch
@nogc nothrow @system
unittest {
  import std.math : isClose;
  TestHost host = { mallocNew!Synth2Client() };
  scope (exit) destroyFree(host.client);

  // Check initial pitch.
  host.setParam!(Params.oscMix)(1.0);
  host.setParam!(Params.osc2Track)(false);
  host.processAudio();
  assert(isClose(host.client._osc2.lastUsedWave.freq, 440));

  // Check pitch is 1 octave down.
  host.setParam!(Params.osc2Pitch)(-12);
  host.processAudio();
  assert(isClose(host.client._osc2.lastUsedWave.freq, 220));

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
  assert(host.paramChangeOutputs!(Params.ampVel)(0.0));
}

/// Test filter
@nogc nothrow @system
unittest {
  TestHost host = { mallocNew!Synth2Client() };
  scope (exit) destroyFree(host.client);
  foreach (fkind; EnumMembers!FilterKind) {
    host.setParam!(Params.filterKind)(fkind);
    assert(host.paramChangeOutputs!(Params.filterCutoff)(0.5));
    if (fkind != FilterKind.HP6 && fkind != FilterKind.LP6) {
      assert(host.paramChangeOutputs!(Params.filterQ)(0.5));
    }
  }

  host.setParam!(Params.filterCutoff)(0);
  assert(host.paramChangeOutputs!(Params.filterTrack)(1.0));
  host.setParam!(Params.filterEnvAmount)(1.0);
  assert(host.paramChangeOutputs!(Params.filterUseVelocity)(true));
  assert(host.paramChangeOutputs!(Params.filterAttack)(1.0));
  assert(host.paramChangeOutputs!(Params.saturation)(1.0));

  // host.frames = 1000;
  // assert(host.paramChangeOutputs!(Params.filterDecay)(10.0));
  // assert(host.paramChangeOutputs!(Params.filterSustain)(-10));
  // assert(host.paramChangeOutputs!(Params.filterRelease)(1.0));
}

/// Test filter
@nogc nothrow @system
unittest {
  TestHost host = { mallocNew!Synth2Client() };
  scope (exit) destroyFree(host.client);

  host.frames = 1000;
  host.setParam!(Params.oscMix)(0.5);
  host.setParam!(Params.oscSubVol)(0.5);
  host.setParam!(Params.osc1Waveform)(Waveform.pulse);
  assert(host.paramChangeOutputs!(Params.menvAmount)(1.0));
  host.setParam!(Params.menvAmount)(1.0);

  foreach (dest; EnumMembers!MEnvDest) {
    host.setParam!(Params.menvDest)(dest);
    assert(host.paramChangeOutputs!(Params.menvAmount)(0.5));
    assert(host.paramChangeOutputs!(Params.menvAttack)(1.0));
    assert(host.paramChangeOutputs!(Params.menvDecay)(1.0));
  }
}

/// Test effect
@nogc nothrow @system
unittest {
  TestHost host = { mallocNew!Synth2Client() };
  scope (exit) destroyFree(host.client);

  host.frames = 1000;
  host.setParam!(Params.effectMix)(1.0);

  static immutable kinds = [EnumMembers!EffectKind];
  foreach (EffectKind kind; kinds) {
    host.setParam!(Params.effectKind)(kind);
    assert(host.paramChangeOutputs!(Params.effectCtrl1)(0.001));
    // assert(host.paramChangeOutputs!(Params.effectCtrl2)(0.1));
  }
}

/// Test EQ
@nogc nothrow @system
unittest {
  TestHost host = { mallocNew!Synth2Client() };
  scope (exit) destroyFree(host.client);

  assert(host.paramChangeOutputs!(Params.eqLevel)(-1));
  assert(host.paramChangeOutputs!(Params.eqPan)(-1));
  assert(host.paramChangeOutputs!(Params.eqTone)(-1));
  assert(host.paramChangeOutputs!(Params.eqTone)(1));
}

/// Test LFO
@nogc nothrow @system
unittest {
  TestHost host = { mallocNew!Synth2Client() };
  scope (exit) destroyFree(host.client);

  assert(host.paramChangeOutputs!(Params.lfo1Amount)(1));
  assert(host.paramChangeOutputs!(Params.lfo2Amount)(1));

  host.setParam!(Params.oscMix)(0.5);
  host.setParam!(Params.osc1Waveform)(Waveform.pulse);
  host.setParam!(Params.lfo1Amount)(1.0);
  host.frames = 1000;
  host.noteOff = true;
  assert(host.paramChangeOutputs!(Params.lfo1Dest)(LfoDest.amp));
  foreach (dest; EnumMembers!LfoDest) {
    host.setParam!(Params.lfo1Dest)(dest);
    assert(host.paramChangeOutputs!(Params.lfo1Speed)(1));
    assert(host.paramChangeOutputs!(Params.lfo1Wave)(Waveform.sine));
    assert(host.paramChangeOutputs!(Params.lfo1Sync)(false));
    assert(host.paramChangeOutputs!(Params.lfo1Mul)(Multiplier.dot));
    assert(host.paramChangeOutputs!(Params.lfo1Trigger)(true));
  }
}

/// Test voice
@nogc nothrow @system
unittest {
  TestHost host = { mallocNew!Synth2Client() };
  scope (exit) destroyFree(host.client);

  assert(host.paramChangeOutputs!(Params.voiceKind)(VoiceKind.mono));
  assert(host.paramChangeOutputs!(Params.voiceKind)(VoiceKind.legato));

  host.frames = 1000;
  host.setParam!(Params.voiceKind)(VoiceKind.legato);
  assert(host.paramChangeOutputs!(Params.voicePortament)(1));
  // TODO: assert(host.paramChangeOutputs!(Params.voicePortamentAuto)(false));
}

/// Test Chorus
@nogc nothrow @system
unittest {
  TestHost host = { mallocNew!Synth2Client() };
  scope (exit) destroyFree(host.client);

  host.frames = 1000;
  // TODO: test On/Off sound diff.
  host.setParam!(Params.chorusOn)(true);
  host.setParam!(Params.chorusLevel)(1.0);
  host.setParam!(Params.chorusMulti)(2);
  assert(host.paramChangeOutputs!(Params.chorusMulti)(1));
  assert(host.paramChangeOutputs!(Params.chorusMulti)(3));
  assert(host.paramChangeOutputs!(Params.chorusMulti)(4));
  assert(host.paramChangeOutputs!(Params.chorusTime)(40));
  assert(host.paramChangeOutputs!(Params.chorusDepth)(0.5));
  assert(host.paramChangeOutputs!(Params.chorusRate)(20));
  assert(host.paramChangeOutputs!(Params.chorusFeedback)(1));
  assert(host.paramChangeOutputs!(Params.chorusLevel)(1));
  assert(host.paramChangeOutputs!(Params.chorusWidth)(1));
}
