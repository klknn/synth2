/**
Ocillator module.

Copyright: klknn 2021.
Copyright: Elias Batek 2018.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module synth2.oscillator;

import mir.math : sin, PI, fmin;

import dplug.core.math : TAU, convertMIDINoteToFrequency;
import dplug.client.midi : MidiMessage, MidiStatus;


/// Waveform kind.
enum WaveForm {
  saw,
  sine,
  square,
  triangle,
}

/// Waveform oscilator.
struct Oscillator {
  float phase = 0;
  float sampleRate;
  WaveForm waveForm;

  @safe nothrow @nogc:

  float oscilate(float frequency) {
    this.phase += frequency * TAU / this.sampleRate;
    this.phase %= TAU;
    final switch (this.waveForm) {
      case WaveForm.saw:
        return 1.0 - (this.phase / PI);
      case WaveForm.sine:
        return sin(this.phase);
      case WaveForm.square:
        return (this.phase <= PI) ? 1.0 : -1.0;
      case WaveForm.triangle:
        return fmin(this.phase, PI - this.phase) / PI;
    }
  }
}

/// MIDI voice status.
struct VoiceStatus {
  bool isPlaying = false;
  int note = -1;
}

/// Synthesizer that generates WAV samples by given params and midi.
struct Synth
{
 public:
  @safe @nogc nothrow:

  enum voicesCount = 4;

  // Setters
  void setWaveForm(WaveForm value) {
    foreach (ref o; _oscs) {
      o.waveForm = value;
    }
  }

  void setSampleRate(float sampleRate) {
    foreach (i; 0 .. voicesCount) {
      _voices[i].isPlaying = false;
      _oscs[i].sampleRate = sampleRate;
    }
  }

  void setMidi(const ref MidiMessage msg) @system {
    switch (cast(MidiStatus) msg.statusType()) {
      case MidiStatus.noteOn:
        markNoteOn(msg.noteNumber());
        return;
      case MidiStatus.noteOff:
        markNoteOff(msg.noteNumber());
        return;
      default:
        // TODO
        return;
    }
  }

  /// Synthesizes waveform sample.
  float synthesize() @system {
    float sample = 0;
    foreach (i; 0 .. voicesCount) {
      if (!_voices[i].isPlaying) continue;

      auto freq = convertMIDINoteToFrequency(_voices[i].note);
      sample += _oscs[i].oscilate(freq);
    }
    return sample / voicesCount;
  }

 private:
  // TODO: use optional
  int getUnusedVoiceId() {
    foreach (i; 0 .. voicesCount) {
      if (!_voices[i].isPlaying) {
        return cast(int) i;
      }
    }
    return -1;
  }

  void markNoteOn(int note) {
    const i = this.getUnusedVoiceId();
    if (i == -1) {
      /*
        No voice available

        well, one could override one, but:
        - always overriding the 1st one is lame
        - a smart algorithm would make this example more complicated
      */
      return;
    }
    _voices[i].note = note;
    _voices[i].isPlaying = true;
  }

  void markNoteOff(int note) {
    foreach (ref v; this._voices) {
      if (v.isPlaying && (v.note == note)) {
        v.isPlaying = false;
      }
    }
  }
    
  VoiceStatus[voicesCount] _voices;
  Oscillator[voicesCount] _oscs;
}
