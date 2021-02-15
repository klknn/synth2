/**
Ocillator module.

Copyright: klknn 2021.
Copyright: Elias Batek 2018.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module oscillator;

import std.math : sin, PI;

import dplug.core.math : TAU, convertMIDINoteToFrequency;


enum WaveForm {
  saw,
  sine,
  square,
}

struct Oscillator {
  float phase = 0;
  float sampleRate;
  WaveForm waveForm;

  @safe nothrow @nogc:

  float synthesizeNext(float frequency) {
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
    while (this.phase >= TAU) {
      this.phase -= TAU;
    }
    return sample;
  }
}

struct VoiceStatus {
  bool isPlaying = false;
  int note = -1;
}

class Synth(size_t voicesCount)
{
  static assert(voicesCount > 0, "A synth must have at least 1 voice.");

 public:
  @safe @nogc nothrow:

  this(WaveForm waveForm) @system {
    foreach (i; 0 .. voicesCount) {
      _oscs[i].waveForm = waveForm;
    }
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
      auto f = convertMIDINoteToFrequency(_voices[i].note);
      auto s = !_voices[i].isPlaying ? 0.0 : _oscs[i].synthesizeNext(f);
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
