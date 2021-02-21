/**
Ocillator module.

Copyright: klknn 2021.
Copyright: Elias Batek 2018.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module synth2.oscillator;

import std.math : isNaN;

import dplug.core.math : TAU, convertDecibelToLinearGain, convertMIDINoteToFrequency;
import dplug.client.midi : MidiMessage, MidiStatus;
import mir.random : rand;
import mir.random.engine.xoshiro : Xoshiro128StarStar_32;
import mir.math : sin, PI, fmin, log2, exp2;

import synth2.envelope : ADSR;

@safe nothrow @nogc:


/// Waveform kind.
enum Waveform {
  sine,
  saw,
  pulse,
  triangle,
  noise,
}

static immutable waveformNames = [__traits(allMembers, Waveform)];

/// Waveform range.
struct WaveformRange {
  float freq = 440;
  float phase = 0;  // [0 .. 2 * PI (=TAU)]
  float normalized = false;
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
        return this.phase <= this.pulseWidth * TAU ? 1f : -1f;
      case Waveform.triangle:
        return 2f * fmin(this.phase, TAU - this.phase) / PI - 1f;
      case Waveform.noise:
        return rand!float(this.rng);
    }    
  }
  
  pure void popFront() {
    this.phase += this.freq * TAU / this.sampleRate;
    this.normalized = false;
    if (this.phase >= TAU) {
      this.phase %= TAU;
      this.normalized = true;
    }
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
      _waves[i].phase = 0;
      _envelopes[i].frameWidth = 1f / sampleRate;
      _envelopes[i].attack;
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
      case MidiStatus.pitchBend:
        _pitchBend = msg.pitchBend();
        assert(false);
        // break;
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
  
  void setNoteDetune(float val) {
    _noteDiff = val;
  }

  float note(VoiceStatus v) const {
    return (_noteTrack ? v.note : 69.0f) + _noteDiff + _noteDetune
        // TODO: fix pitch bend
        + _pitchBend * _pitchBendWidth;
  }

  void synchronize(const ref Oscillator src) {
    foreach (i, ref w; _waves) {
      if (src._waves[i].normalized) {
        w.phase = 0f;
      }
    }
  }

  void setFM(float scale, const ref Oscillator mod) {
    foreach (i; 0 .. voicesCount) {
      _waves[i].phase += scale * mod.frontNth(i);
    }
  }

  void setADSR(float a, float d, float s, float r) {
    foreach (ref ADSR e; _envelopes) {
      e.attackTime = a;
      e.decayTime = d;
      e.sustainLevel = s;
      e.releaseTime = r;
    }
  }
  
  /// Synthesizes waveform sample.
  float synthesize() @system {
    this.popFront();
    return this.front;
  }

  enum empty = false;

  /// Returns sum of amplitudes of _waves at the current phase.
  float front() const {
    float sample = 0;
    foreach (i; 0 .. voicesCount) {
      sample += frontNth(i);
    }
    return sample / voicesCount;
  }

  /// Increments phase in _waves.
  void popFront() {
    foreach (i, ref w; _waves) {
      w.popFront();
      _envelopes[i].popFront();
    }
  }

  /// Updates frequency by MIDI and params.
  void updateFreq() @system {
    foreach (i, ref w; _waves) {
      if (_voices[i].isPlaying) {
        w.freq = convertMIDINoteToFrequency(this.note(_voices[i]));
      }
    }
  }

  auto waves() const {
    return _waves;
  }

  auto voices() const {
    return _voices;
  }

  auto lastUsedWave() const {
    return _waves[_lastUsedId];
  }
  
 private:
  float frontNth(size_t i) const {
    auto v = _voices[i];
    if (!v.isPlaying) return 0f;
    return _waves[i].front * v.gain * _envelopes[i].front;
  }

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
    _lastUsedId = i;
    _envelopes[i].attack();
  }

  void markNoteOff(int note) {
    foreach (i, ref v; this._voices) {
      if (v.isPlaying && (v.note == note)) {
        v.isPlaying = false;
        _envelopes[i].release();
      }
    }
  }

  // voice global config
  float _noteDiff = 0.0;
  float _noteDetune = 0.0;
  bool _noteTrack = true;
  float _velocitySense = 0.0;
  float _pitchBend = 0.0;
  float _pitchBendWidth = 2.0;
  size_t _lastUsedId = 0;

  VoiceStatus[voicesCount] _voices;
  WaveformRange[voicesCount] _waves;
  ADSR[voicesCount] _envelopes;
}

@system
unittest {
  import dplug.client.midi;

  auto m = makeMidiMessagePitchWheel(0, 0, 0.5);
  assert(m.pitchWheel == 0.5);
}
