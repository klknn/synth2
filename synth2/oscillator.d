/**
Ocillator module.

Copyright: klknn 2021.
Copyright: Elias Batek 2018.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module synth2.oscillator;

import std.math : sin, PI;

import dplug.core.math : TAU, convertMIDINoteToFrequency;


/// Waveform kind.
enum WaveForm {
  saw,
  sine,
  square,
}

/// Waveform oscilator.
struct Oscillator {
  float phase = 0;
  float sampleRate;
  WaveForm waveForm;

  @safe nothrow @nogc:

  float oscilate(float frequency) {
    float sample = void;
    final switch (this.waveForm) {
      case WaveForm.saw:
        sample = 1.0 - (this.phase / PI);
        break;
      case WaveForm.sine:
        sample = sin(this.phase);
        break;
      case WaveForm.square:
        sample = (this.phase <= PI) ? 1.0 : -1.0;
        break;
    }
    this.phase += frequency * TAU / this.sampleRate;
    this.phase %= TAU;
    return sample;
  }
}

/// MIDI voice status.
struct VoiceStatus {
  bool isPlaying = false;
  int note = -1;
}

/// Synthesizer integrates components.
struct Synth
{
 public:
  @safe @nogc nothrow:

  enum voicesCount = 4;
  
  this(WaveForm waveForm) @system {
    setWaveForm(waveForm);
  }

  bool isPlaying() pure {
    foreach(v; this._voices) {
      if (v.isPlaying) {
        return true;
      }
    }
    return false;
  }

  WaveForm waveForm() pure {
    return this._oscs[0].waveForm;
  }

  void setWaveForm(WaveForm value) {
    foreach (ref o; _oscs) {
      o.waveForm = value;
    }
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

  void reset(float sampleRate) {
    foreach (i; 0 .. voicesCount) {
      _voices[i].isPlaying = false;
      _oscs[i].sampleRate = sampleRate;
    }
  }

  float synthesizeNext() @system {
    float sample = 0;
    foreach (i; 0 .. voicesCount) {
      if (!_voices[i].isPlaying) continue;

      auto f = convertMIDINoteToFrequency(_voices[i].note);
      auto s = _oscs[i].oscilate(f);
      sample += s / voicesCount; // synth + lower volume
    }
    return sample;
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

  VoiceStatus[voicesCount] _voices;
  Oscillator[voicesCount] _oscs;
}
