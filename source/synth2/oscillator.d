/**
Ocillator module.

Copyright: klknn 2021.
Copyright: Elias Batek 2018.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module synth2.oscillator;

import std.math : isNaN;

import dplug.core.math : convertDecibelToLinearGain;
import dplug.client.midi : MidiMessage, MidiStatus;
import mir.math : log2, exp2, fastmath, PI;

import synth2.envelope : ADSR;
import synth2.waveform : Waveform, waveformNames, WaveformRange;

@safe nothrow @nogc:

float convertMIDINoteToFrequency(float note) @fastmath pure
{
    return 440.0f * exp2((note - 69.0f) / 12.0f);
}


/// Mono voice status (subosc).
struct VoiceStatus {
  int note = -1;
  private float gain = 1f;

  WaveformRange wave;
  ADSR envelope;

  @nogc nothrow @safe @fastmath:

  pure bool isPlaying() const {
    return !this.envelope.empty;
  }

  float front() const {
    if (!this.isPlaying) return 0f;
    return this.wave.front * this.gain * this.envelope.front;
  }

  pure void popFront() {
    this.wave.popFront();
    this.envelope.popFront();
  }

  pure void setSampleRate(float sampleRate) {
    this.wave.sampleRate = sampleRate;
    this.wave.phase = 0;
    this.envelope.setSampleRate(sampleRate);
  }

  pure void play(int note, float gain) {
    this.gain = gain;
    this.note = note;
    this.envelope.attack();
  }
}

/// Maps 0 to 127 into Decibel domain with affine transformation.
/// For example, velocities [0, 68, 127] will be mapped to
/// [-20, -0.9, 0] dB if sensitivity = 1.0, bias = 1e-3
/// [-11, -1.9, -1] if sensitivity = 0.5, bias = 1e-3
/// [-10, -10, -10] if sensitivity = 0.0, bias = 1e-3
float velocityToDB(int velocity, float sensitivity = 1.0, float bias = 1e-1) @fastmath pure {
  assert(0 <= velocity && velocity <= 127);
  auto scaled = (velocity / 127f - bias) * sensitivity + bias;
  return log2(scaled + 1e-6);
}

///
@system pure unittest {
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
  @safe @nogc nothrow @fastmath:

  enum voicesCount = 16;

  // Setters
  pure void setInitialPhase(float value) {
    this._initialPhase = value;
  }

  pure void setWaveform(Waveform value) {
    foreach (ref v; _voices) {
      v.wave.waveform = value;
    }
  }

  pure void setPulseWidth(float value) {
    foreach (ref v; _voices) {
      v.wave.pulseWidth = value;
    }
  }

  pure void setSampleRate(float sampleRate) {
    foreach (ref v; _voices) {
      v.setSampleRate(sampleRate);
    }
  }

  pure void setVelocitySense(float value) {
    this._velocitySense = value;
  }

  void setMidi(MidiMessage msg) @system {
    if (msg.isNoteOn) {
      markNoteOn(msg);
    }
    if (msg.isNoteOff) {
      markNoteOff(msg.noteNumber());
    }
    if (msg.isPitchBend) {
      _pitchBend = msg.pitchBend();
    }
  }

  pure void setNoteTrack(bool b) {
    _noteTrack = b;
  }

  pure void setNoteDiff(float note) {
    _noteDiff = note;
  }

  pure void setNoteDetune(float val) {
    _noteDiff = val;
  }

  pure float note(const ref VoiceStatus v) const {
    return (_noteTrack ? v.note : 69.0f) + _noteDiff + _noteDetune
        // TODO: fix pitch bend
        + _pitchBend * _pitchBendWidth;
  }

  pure void synchronize(const ref Oscillator src) {
    foreach (i; 0 .. voicesCount) {
      if (src._voices[i].wave.normalized) {
        _voices[i].wave.phase = 0f;
      }
    }
  }

  void setFM(float scale, const ref Oscillator mod) {
    foreach (i; 0 .. voicesCount) {
      _voices[i].wave.phase += scale * mod._voices[i].front;
    }
  }

  pure void setADSR(float a, float d, float s, float r) {
    foreach (ref v; _voices) {
      v.envelope.attackTime = a;
      v.envelope.decayTime = d;
      v.envelope.sustainLevel = s;
      v.envelope.releaseTime = r;
    }
  }

  enum empty = false;

  /// Returns sum of amplitudes of _waves at the current phase.
  float front() const {
    float sample = 0;
    foreach (ref v; _voices) {
      sample += v.front;
    }
    return sample / voicesCount;
  }

  /// Increments phase in _waves.
  pure void popFront() {
    foreach (ref v; _voices) {
      v.popFront();
    }
  }

  /// Updates frequency by MIDI and params.
  pure void updateFreq() @system {
    foreach (ref v; _voices) {
      if (v.isPlaying) {
        v.wave.freq = convertMIDINoteToFrequency(this.note(v));
      }
    }
  }

  pure bool isPlaying() const {
    foreach (ref v; _voices) {
      if (v.isPlaying) return true;
    }
    return false;
  }

  pure WaveformRange lastUsedWave() const {
    return _voices[_lastUsedId].wave;
  }

 private:

  // TODO: use optional
  pure int getUnusedVoiceId() const {
    foreach (i; 0 .. voicesCount) {
      if (!_voices[i].isPlaying) {
        return cast(int) i;
      }
    }
    return -1;
  }

  pure void markNoteOn(MidiMessage midi) @system {
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
    const db =  velocityToDB(midi.noteVelocity(), this._velocitySense);
    _voices[i].play(midi.noteNumber(), convertDecibelToLinearGain(db));
    if (this._initialPhase != -PI)
      _voices[i].wave.phase = this._initialPhase;
    _lastUsedId = i;
  }

  pure void markNoteOff(int note) {
    foreach (ref v; this._voices) {
      if (v.isPlaying && v.note == note) {
        v.envelope.release();
      }
    }
  }

  // voice global config
  float _initialPhase = 0.0;
  float _noteDiff = 0.0;
  float _noteDetune = 0.0;
  bool _noteTrack = true;
  float _velocitySense = 0.0;
  float _pitchBend = 0.0;
  float _pitchBendWidth = 2.0;
  size_t _lastUsedId = 0;

  VoiceStatus[voicesCount] _voices;
}
