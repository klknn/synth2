/**
   Synth2 virtual analog syntesizer.

   Copyright: klknn 2021.
   Copyright: Elias Batek 2018.
   License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module synth2.client;


import dplug.core : makeVec, mallocNew;
import dplug.client : Client, DLLEntryPoint, EnumParameter, LinearFloatParameter,
  BoolParameter, GainParameter, IntegerParameter, IGraphics, LegalIO, Parameter,
  parsePluginInfo, pluginEntryPoints, PluginInfo, TimeInfo;
import mir.math : exp2;

import synth2.gui : Synth2GUI;
import synth2.oscillator : Oscillator, WaveForm;

// This define entry points for plugin formats,
// depending on which version identifiers are defined.
mixin(pluginEntryPoints!Synth2Client);

enum Params : int {
  osc1WaveForm,
  // osc1Det,
  // osc1FM,
  osc2WaveForm,
  // osc2Ring,
  // osc2Sync,
  osc2Track,
  osc2Pitch,
  osc2Fine,
  oscMix,
  // oscKeyShift,
  // oscPulseWidth,
  // oscPhase,
  // oscTune,
  oscSubWaveForm,
  oscSubVol,
  oscSubOct,
}

immutable waveFormNames = [__traits(allMembers, WaveForm)];

/// Polyphonic digital-aliasing synth
class Synth2Client : Client {
 public:
  nothrow @nogc:

  // NOTE: this method will not call until GUI required (lazy)
  override IGraphics createGraphics() {
    _gui = mallocNew!Synth2GUI(
        this.param(Params.osc1WaveForm),
    );
    return _gui;
  }

  override PluginInfo buildPluginInfo() {
    // Plugin info is parsed from plugin.json here at compile time.
    static immutable info = parsePluginInfo(import("plugin.json"));
    return info;
  }

  override Parameter[] buildParameters() {
    auto params = makeVec!Parameter();

    // Osc 1 and 2.
    params ~= mallocNew!EnumParameter(
        Params.osc1WaveForm, "Osc 1: Waveform", waveFormNames, WaveForm.sine);
    params ~= mallocNew!EnumParameter(
        Params.osc2WaveForm, "Osc 2: Waveform", waveFormNames, WaveForm.triangle);
    params ~= mallocNew!BoolParameter(Params.osc2Track, "Osc 2: Track", true);
    params ~= mallocNew!IntegerParameter(
        // TODO: check synth1 default (440hz?)
        Params.osc2Pitch, "Osc 2: Pitch", "", -69, 68, 0);
    params ~= mallocNew!LinearFloatParameter(
        Params.osc2Fine, "Osc 2: Fine", "", -1.0, 1.0, 0.0);
    params ~= mallocNew!LinearFloatParameter(
        Params.oscMix, "Osc 1&2: Mix", "", 0f, 1f, 0f);

    // Osc sub.
    params ~= mallocNew!EnumParameter(
        Params.oscSubWaveForm, "Osc sub: Waveform", waveFormNames, WaveForm.sine);
    params ~= mallocNew!GainParameter(
        // TODO: check synth1 max vol.
        Params.oscSubVol, "Osc sub: Vol", 0.0f, -float.infinity);
    params ~= mallocNew!BoolParameter(Params.oscSubOct, "Osc sub: -1 Oct", false);

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
    this._osc1.setSampleRate(sampleRate);
    this._osc2.setSampleRate(sampleRate);
    this._oscSub.setSampleRate(sampleRate);
  }

  override void processAudio(const(float*)[] inputs, float*[] outputs,
                             int frames, TimeInfo info) {
    // Bind params.
    _osc1.setWaveForm(readParam!WaveForm(Params.osc1WaveForm));

    _osc2.setWaveForm(readParam!WaveForm(Params.osc2WaveForm));
    _osc2.setNoteTrack(readParam!bool(Params.osc2Track));
    _osc2.setNoteDiff(readParam!int(Params.osc2Pitch) +
                      readParam!float(Params.osc2Fine));

    _oscSub.setWaveForm(readParam!WaveForm(Params.oscSubWaveForm));
    _oscSub.setNoteDiff(readParam!bool(Params.oscSubOct) ? -12 : 0);

    // Bind MIDI.
    foreach (msg; this.getNextMidiMessages(frames)) {
      _osc1.setMidi(msg);
      _osc2.setMidi(msg);
      _oscSub.setMidi(msg);
    }
    // Generate samples.
    const oscMix = readParam!float(Params.oscMix);
    const oscSubVol = readParam!float(Params.oscSubVol);
    foreach (frame; 0 .. frames) {
      outputs[0][frame] = (1.0 - oscMix) *_osc1.synthesize()
                          + oscMix * _osc2.synthesize()
                          + exp2(oscSubVol) * _oscSub.synthesize();
    }
    foreach (chan; 1 .. outputs.length) {
      outputs[chan][0 .. frames] = outputs[0][0 .. frames];
    }
  }

 private:
  Oscillator _osc1, _osc2, _oscSub;
  Synth2GUI _gui;
}
