/**
   Synth2 virtual analog syntesizer.

   Copyright: klknn 2021.
   Copyright: Elias Batek 2018.
   License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module synth2.main;

import dplug.core : makeVec, mallocNew;
import dplug.client : Client, DLLEntryPoint, EnumParameter, LegalIO, Parameter,
  parsePluginInfo, pluginEntryPoints, PluginInfo, TimeInfo;

import synth2.oscillator : Synth, WaveForm;

// This define entry points for plugin formats, 
// depending on which version identifiers are defined.
mixin(pluginEntryPoints!Synth2Client);

enum Params : int {
  osc1WaveForm,
}

immutable waveFormNames = [__traits(allMembers, WaveForm)];


/// Polyphonic digital-aliasing synth
class Synth2Client : Client {
 public:
  nothrow @nogc:

  override PluginInfo buildPluginInfo() {
    // Plugin info is parsed from plugin.json here at compile time.
    static immutable info = parsePluginInfo(import("plugin.json"));
    return info;
  }

  override Parameter[] buildParameters() {
    auto params = makeVec!Parameter();
    params ~= mallocNew!EnumParameter(Params.osc1WaveForm, "Osc 1: Waveform",
                                      waveFormNames, WaveForm.sine);
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
    this._synth.setSampleRate(sampleRate);
  }

  override void processAudio(const(float*)[] inputs, float*[] outputs,
                             int frames, TimeInfo info) {
    // Bind params.
    _synth.setWaveForm(readParam!WaveForm(Params.osc1WaveForm));
    // Bind MIDI.
    foreach (msg; this.getNextMidiMessages(frames)) {
      _synth.setMidi(msg);
    }
    // Generate samples.
    foreach (frame; 0 .. frames) {
      outputs[0][frame] = _synth.synthesize();
    }
    foreach (chan; 1 .. outputs.length) {
      outputs[chan][0 .. frames] = outputs[0][0 .. frames];
    }
  }
  
 private:
  Synth _synth;
}
