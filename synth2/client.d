/**
   Synth2 virtual analog syntesizer.

   Copyright: klknn 2021.
   Copyright: Elias Batek 2018.
   License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module synth2.client;

import std.traits : EnumMembers;

import dplug.core : destroyFree, makeVec, mallocNew;
import dplug.client : Client, DLLEntryPoint, EnumParameter, LinearFloatParameter,
  BoolParameter, GainParameter, IntegerParameter, IGraphics, LegalIO, Parameter,
  parsePluginInfo, pluginEntryPoints, PluginInfo, TimeInfo;
import mir.math : exp2, log;

import synth2.gui : Synth2GUI;
import synth2.oscillator : Oscillator, Waveform;

// This define entry points for plugin formats,
// depending on which version identifiers are defined.
mixin(pluginEntryPoints!Synth2Client);

enum Params : int {
  /// Oscillator section
  osc1Waveform,
  osc1Det,
  // osc1FM,
  osc2Waveform,
  // osc2Ring,
  osc2Sync,
  osc2Track,
  osc2Pitch,
  osc2Fine,
  oscMix,
  // oscKeyShift,
  oscPulseWidth,
  // oscPhase,
  // oscTune,
  oscSubWaveform,
  oscSubVol,
  oscSubOct,

  /// Amp section
  ampVel,
}

immutable waveFormNames = [__traits(allMembers, Waveform)];

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
    auto params = makeVec!Parameter(EnumMembers!Params.length);

    void build(T, Args...)(Args args) {
      params[args[0]] = mallocNew!T(args);
    }

    // Osc 1 and 2.
    build!EnumParameter(
        Params.osc1Waveform, "Osc1/Wave", waveFormNames, Waveform.sine);
    build!LinearFloatParameter(Params.osc1Det, "Osc1/Det", "", 0, 1, 0);
    build!EnumParameter(
        Params.osc2Waveform, "Osc2/Wave", waveFormNames, Waveform.triangle);
    build!BoolParameter(Params.osc2Track, "Osc 2: Track", true);
    // TODO: check synth1 default (440hz?)
    build!IntegerParameter(Params.osc2Pitch, "Osc 2: Pitch", "", -69, 68, 0);
    build!LinearFloatParameter(
        Params.osc2Fine, "Osc 2: Fine", "", -1.0, 1.0, 0.0);
    build!BoolParameter(Params.osc2Sync, "Osc2/Sync", false);
    build!LinearFloatParameter(
        Params.oscMix, "Osc 1&2: Mix", "", 0f, 1f, 0f);
    build!LinearFloatParameter(
        Params.oscPulseWidth, "Osc 1&2: P/W", "", 0f, 1f, 0.5f);

    // Osc sub.
    build!EnumParameter(
        Params.oscSubWaveform, "Osc sub: Waveform", waveFormNames, Waveform.sine);
    build!GainParameter(
        // TODO: check synth1 max vol.
        Params.oscSubVol, "Osc sub: Vol", 0.0f, -float.infinity);
    build!BoolParameter(Params.oscSubOct, "Osc sub: -1 Oct", false);

    // Amp.
    build!LinearFloatParameter(
        Params.ampVel, "Amp: Vel", "", 0, 1.0, 0);
    
    return params.releaseData();
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
  }

  override void processAudio(const(float*)[] inputs, float*[] outputs,
                             int frames, TimeInfo info) {
    // TODO: use info.timeInSamples to set the RNG status.

    // Bind Osc params.
    const pw = readParam!float(Params.oscPulseWidth);
    const vel = readParam!float(Params.ampVel);
    foreach (ref _osc1; _osc1s) {
      _osc1.setWaveform(readParam!Waveform(Params.osc1Waveform));
      _osc1.setPulseWidth(pw);
      _osc1.setVelocitySense(vel);
    }

    _osc2.setWaveform(readParam!Waveform(Params.osc2Waveform));
    _osc2.setPulseWidth(pw);
    _osc2.setNoteTrack(readParam!bool(Params.osc2Track));
    _osc2.setNoteDiff(readParam!int(Params.osc2Pitch) +
                      readParam!float(Params.osc2Fine));
    _osc2.setVelocitySense(vel);

    _oscSub.setWaveform(readParam!Waveform(Params.oscSubWaveform));
    _oscSub.setNoteDiff(readParam!bool(Params.oscSubOct) ? -12 : 0);
    _oscSub.setVelocitySense(vel);
    
    // Bind MIDI.
    foreach (msg; this.getNextMidiMessages(frames)) {
      foreach (ref o1; _osc1s) {
        o1.setMidi(msg);
      }
      _osc2.setMidi(msg);
      _oscSub.setMidi(msg);
    }
    // Generate samples.
    const osc1Det = readParam!float(Params.osc1Det);
    foreach (i; 1 .. _osc1s.length) {
      _osc1s[i].setNoteDetune(log(osc1Det + 1f) * 2 *
                              log(i + 1f) / log(cast(float) _osc1s.length));
    }
    const oscMix = readParam!float(Params.oscMix);
    const oscSubVol = readParam!float(Params.oscSubVol);
    const sync = readParam!bool(Params.osc2Sync);
    foreach (frame; 0 .. frames) {
      float o1 = _osc1s[0].synthesize();
      if (osc1Det != 0) {
        foreach (ref o; _osc1s[1 .. $]) {
          o1 += o.synthesize();
        }
      }
      float output = (1.0 - oscMix) * o1;
      if (sync) {
        _osc2.synchronize(_osc1s[0]);
      }
      output += oscMix * _osc2.synthesize();
      output += exp2(oscSubVol) * _oscSub.synthesize();

      outputs[0][frame] = output;
    }
    foreach (chan; 1 .. outputs.length) {
      outputs[chan][0 .. frames] = outputs[0][0 .. frames];
    }
  }

 private:
  Oscillator _osc2, _oscSub;
  Oscillator[8] _osc1s;  // +7 for detune
  Synth2GUI _gui;
}

///
@nogc nothrow @system unittest {
  Synth2Client c = mallocNew!Synth2Client();
  c.reset(44100, 32, 0, 2);

  float*[2] inputs, outputs;
  inputs[0] = null;
  inputs[1] = null;
  float[8][2] outputFrames;
  outputs[0] = &outputFrames[0][0];
  outputs[1] = &outputFrames[1][0];

  TimeInfo info;
  c.processAudio(inputs[], outputs[], 8, info);
  c.destroyFree();
}
