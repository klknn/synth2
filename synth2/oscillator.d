/**
Ocillator module.

Copyright: klknn 2021.
Copyright: Elias Batek 2018.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module synth2.oscillator;

import mir.random;
import mir.math : sin, PI, fmin;

import dplug.core.math : TAU, convertMIDINoteToFrequency;
import dplug.client.midi : MidiMessage, MidiStatus;


/// Waveform kind.
enum WaveForm {
  sine,
  saw,
  pulse,
  triangle,
  noise,
}

/// Waveform generator.
struct WaveGenerator {
  float phase = 0;
  float sampleRate = 44100;
  WaveForm waveForm = WaveForm.sine;

  @safe nothrow @nogc:

  float oscilate(float frequency) {
    this.phase += frequency * TAU / this.sampleRate;
    this.phase %= TAU;
    final switch (this.waveForm) {
      case WaveForm.saw:
        return 1.0 - (this.phase / PI);
      case WaveForm.sine:
        return sin(this.phase);
      case WaveForm.pulse:
        return (this.phase <= PI) ? 1.0 : -1.0;
      case WaveForm.triangle:
        return fmin(this.phase, PI - this.phase) / PI;
      case WaveForm.noise:
        return rand!float;
    }
  }
}

///
@safe nothrow @nogc unittest {
  WaveGenerator wg;
  wg.waveForm = WaveForm.noise;
  foreach (_; 0 .. 10) {
    auto sample = wg.oscilate(440);
    assert(-1 < sample && sample < 1);
    assert(0 <= wg.phase && wg.phase <= TAU);
  }
}

/// MIDI voice status.
struct VoiceStatus {
  bool isPlaying = false;
  int note = -1;
}

/// Polyphonic oscillator that generates WAV samples by given params and midi.
struct Oscillator
{
 public:
  @safe @nogc nothrow:

  enum voicesCount = 4;

  // Setters
  void setWaveForm(WaveForm value) {
    foreach (ref wg; _wgens) {
      wg.waveForm = value;
    }
  }

  void setSampleRate(float sampleRate) {
    foreach (i; 0 .. voicesCount) {
      _voices[i].isPlaying = false;
      _wgens[i].sampleRate = sampleRate;
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

  void setNoteDiff(float diff) {
    _noteDiff = diff;
  }

  /// Synthesizes waveform sample.
  float synthesize() @system {
    float sample = 0;
    foreach (i; 0 .. voicesCount) {
      if (!_voices[i].isPlaying) continue;

      auto freq = convertMIDINoteToFrequency(_voices[i].note + _noteDiff);
      sample += _wgens[i].oscilate(freq);
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

  float _noteDiff = 0.0;
  VoiceStatus[voicesCount] _voices;
  WaveGenerator[voicesCount] _wgens;
}
