/**
Ocillator module.

Copyright: klknn 2021.
Copyright: Elias Batek 2018.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module synth2.oscillator;

import dplug.core.math : convertDecibelToLinearGain;
import dplug.client.midi : MidiMessage, MidiStatus;
import mir.math : log2, exp2, fastmath, PI;

import synth2.waveform : Waveform, WaveformRange;
import synth2.voice : VoiceStatus;

@safe nothrow @nogc:

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

float convertMIDINoteToFrequency(float note) @fastmath pure
{
    return 440.0f * exp2((note - 69.0f) / 12.0f);
}

/// Polyphonic oscillator that generates WAV samples by given params and midi.
struct Oscillator
{
 public:
  @safe @nogc nothrow @fastmath:

  // Setters
  void setInitialPhase(float value) pure {
    this._initialPhase = value;
  }

  void setWaveform(Waveform value) pure {
    foreach (ref w; _waves) {
      w.waveform = value;
    }
  }

  void setPulseWidth(float value) pure {
    foreach (ref w; _waves) {
      w.pulseWidth = value;
    }
  }

  void setSampleRate(float sampleRate) pure {
    foreach (ref v; _voicesArr) {
      v.setSampleRate(sampleRate);
    }
    foreach (ref w; _wavesArr) {
      w.sampleRate = sampleRate;
      w.phase = 0;
    }
  }

  void setVelocitySense(float value) pure {
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

  void setNoteTrack(bool b) pure {
    _noteTrack = b;
  }

  void setNoteDiff(float note) pure {
    _noteDiff = note;
  }

  void setNoteDetune(float val) pure {
    _noteDiff = val;
  }

  float note(const ref VoiceStatus v) const pure {
    return (_noteTrack ? v.note : 69.0f) + _noteDiff + _noteDetune
        + _pitchBend * _pitchBendWidth;
  }

  void synchronize(const ref Oscillator src) pure {
    foreach (i, ref w; _waves) {
      if (src._waves[i].normalized) {
        w.phase = 0f;
      }
    }
  }

  void setFM(float scale, const ref Oscillator mod) {
    foreach (i, ref w; _waves) {
      w.phase += scale * mod._voices[i].front;
    }
  }

  void setADSR(float a, float d, float s, float r) pure {
    foreach (ref v; _voices) {
      v.setADSR(a, d, s, r);
    }
  }

  enum empty = false;

  /// Returns sum of amplitudes of _waves at the current phase.
  float front() const {
    float sample = 0;
    foreach (i, ref v; _voices) {
      sample += v.front * _waves[i].front;
    }
    return sample / _voicesArr.length;
  }

  /// Increments phase in _waves.
  void popFront() pure {
    foreach (ref v; _voices) {
      v.popFront();
    }
    foreach (ref w; _waves) {
      w.popFront();
    }
  }

  /// Updates frequency by MIDI and params.
  void updateFreq() pure @system {
    foreach (i, ref v; _voices) {
      if (v.isPlaying) {
        _waves[i].freq = convertMIDINoteToFrequency(this.note(v));
      }
    }
  }

  bool isPlaying() const pure {
    foreach (ref v; _voices) {
      if (v.isPlaying) return true;
    }
    return false;
  }

  WaveformRange lastUsedWave() const pure {
    return _waves[_lastUsedId];
  }

  void setVoice(int n, bool legato, float portament, bool autoPortament) {
    assert(n <= _voicesArr.length, "Exceeds allocated voices.");
    assert(0 <= n, "MaxVoices must be positive.");
    _maxVoices = n;
    foreach (ref v; _voices) {
      v.setParams(legato, portament, autoPortament);
    }
  }

 private:
  size_t getNewVoiceId() const pure {
    foreach (i, ref v; _voices) {
      if (!v.isPlaying) {
        return i;
      }
    }
    return (_lastUsedId + 1) % _voices.length;
  }

  void markNoteOn(MidiMessage midi) pure @system {
    const i = this.getNewVoiceId();
    const db =  velocityToDB(midi.noteVelocity(), this._velocitySense);
    _voices[i].play(midi.noteNumber(), convertDecibelToLinearGain(db));
    if (this._initialPhase != -PI)
      _waves[i].phase = this._initialPhase;
    _lastUsedId = i;
  }

  void markNoteOff(int note) pure {
    foreach (ref v; this._voices) {
      v.stop(note);
    }
  }

  inout(VoiceStatus)[] _voices() inout pure {
    return _voicesArr[0 .. _maxVoices];
  }

  inout(WaveformRange)[] _waves() inout pure {
    return _wavesArr[0 .. _maxVoices];
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
  size_t _maxVoices = _voicesArr.length;

  enum numVoices = 16;
  VoiceStatus[numVoices] _voicesArr;
  WaveformRange[numVoices] _wavesArr;
}
