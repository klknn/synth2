/**
Ocillator module.

Copyright: klknn 2021.
Copyright: Elias Batek 2018.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module synth2.oscillator;

private {
import std.math : isNaN;

import dplug.core.math : TAU, convertDecibelToLinearGain, convertMIDINoteToFrequency;
import dplug.client.midi : MidiMessage, MidiStatus;
import mir.random : rand;
import mir.random.engine.xoshiro : Xoshiro128StarStar_32;
import mir.math : sin, PI, fmin, log2, exp2;
}
@safe nothrow @nogc:


/// Waveform kind.
enum Waveform {
  sine,
  saw,
  pulse,
  triangle,
  noise,
}

/// Waveform range.
struct WaveformRange {
  float freq = 440;
  float phase = 0;
  float sampleRate = 44100;
  float pulseWidth = 0.5;
  Waveform waveform = Waveform.sine;
  static rng = Xoshiro128StarStar_32(0u);
  
  @safe nothrow @nogc:

  enum empty = false;
  
  float front() const {
    final switch (this.waveform) {
      case Waveform.saw:
        return 1.0 - this.phase / PI;
      case Waveform.sine:
        return sin(this.phase);
      case Waveform.pulse:
        return this.phase <= this.pulseWidth * TAU ? 1.0 : -1.0;
      case Waveform.triangle:
        return fmin(this.phase, PI - this.phase) / PI;
      case Waveform.noise:
        return rand!float(this.rng);
    }    
  }
  
  pure void popFront() {
    this.phase += this.freq * TAU / this.sampleRate;
    this.phase %= TAU;
  }
}

///
@safe nothrow @nogc unittest {
  import std.range;
  assert(isInputRange!WaveformRange);
  assert(isInfinite!WaveformRange);
  
  WaveformRange w;
  w.waveform = Waveform.noise;
  foreach (_; 0 .. 10) {
    assert(-1 < w.front && w.front < 1);
    assert(0 <= w.phase && w.phase <= TAU);
    w.popFront();
  }
}

/// MIDI per-voice status.
struct VoiceStatus {
  bool isPlaying = false;
  int note = -1;
  float gain = 1f;
}

/// Maps 0 to 127 into Decibel domain with affine transformation.
/// For example, velocities [0, 68, 127] will be mapped to
/// [-20, -0.9, 0] dB if sensitivity = 1.0, bias = 1e-3
/// [-11, -1.9, -1] if sensitivity = 0.5, bias = 1e-3
/// [-10, -10, -10] if sensitivity = 0.0, bias = 1e-3
float velocityToDB(int velocity, float sensitivity = 1.0, float bias = 1e-1) {
  assert(0 <= velocity && velocity <= 127);
  auto scaled = (velocity / 127f - bias) * sensitivity + bias;
  return log2(scaled + 1e-6);
}

///
@system unittest {
  import std.math : approxEqual;
  auto sens = 1.0;
  assert(approxEqual(convertDecibelToLinearGain(velocityToDB(127, sens)), 1f));
  assert(approxEqual(convertDecibelToLinearGain(velocityToDB(68, sens)), 0.9f));
  assert(approxEqual(convertDecibelToLinearGain(velocityToDB(0, sens)), 0.1f));

  sens = 0.0;
  auto g = 0.682188;
  assert(approxEqual(convertDecibelToLinearGain(velocityToDB(127, sens)), g));
  assert(approxEqual(convertDecibelToLinearGain(velocityToDB(68, sens)), g));
  assert(approxEqual(convertDecibelToLinearGain(velocityToDB(0, sens)), g));
}

/// Polyphonic oscillator that generates WAV samples by given params and midi.
struct Oscillator
{
 public:
  @safe @nogc nothrow:

  enum voicesCount = 16;

  // Setters
  void setWaveform(Waveform value) {
    foreach (ref w; _waves) {
      w.waveform = value;
    }
  }

  void setPulseWidth(float value) {
    foreach (ref w; _waves) {
      w.pulseWidth = value;
    }
  }
  
  void setSampleRate(float sampleRate) {
    foreach (i; 0 .. voicesCount) {
      _voices[i].isPlaying = false;
      _waves[i].sampleRate = sampleRate;
    }
  }

  void setVelocitySense(float value) {
    this._velocitySense = value;
  }

  void setMidi(MidiMessage msg) @system {
    switch (cast(MidiStatus) msg.statusType()) {
      case MidiStatus.noteOn:
        markNoteOn(msg);
        break;
      case MidiStatus.noteOff:
        markNoteOff(msg.noteNumber());
        break;
      default:
        // TODO
        break;
    }
  }

  void setNoteTrack(bool b) {
    _noteTrack = b;
  }
  
  void setNoteDiff(float note) {
    _noteDiff = note;
  }

  float note(VoiceStatus v) const {
    return (_noteTrack ? v.note : 69.0f) + _noteDiff;
  }
  
  /// Synthesizes waveform sample.
  float synthesize() @system {
    this.popFront();
    return this.front;
  }

  enum empty = false;
  
  float front() @system {
    float sample = 0;
    foreach (i; 0 .. voicesCount) {
      auto v = _voices[i];
      if (!v.isPlaying) continue;

      _waves[i].freq = convertMIDINoteToFrequency(this.note(_voices[i]));
      sample +=_waves[i].front * v.gain;
    }
    return sample / voicesCount;
  }

  void popFront() {
    foreach (ref w; _waves) {
      w.popFront();
    }
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

  void markNoteOn(MidiMessage midi) @system {
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
    _voices[i].note = midi.noteNumber();
    const db =  velocityToDB(midi.noteVelocity(), this._velocitySense);
    _voices[i].gain = convertDecibelToLinearGain(db);
    _voices[i].isPlaying = true;
  }

  void markNoteOff(int note) {
    foreach (ref v; this._voices) {
      if (v.isPlaying && (v.note == note)) {
        v.isPlaying = false;
      }
    }
  }

  // voice global config
  float _noteDiff = 0.0;
  bool _noteTrack = true;
  float _velocitySense = 0.0;

  VoiceStatus[voicesCount] _voices;
  WaveformRange[voicesCount] _waves;
}
