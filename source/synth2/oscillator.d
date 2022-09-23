/**
Ocillator module.

Copyright: klknn 2021.
Copyright: Elias Batek 2018.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module synth2.oscillator;

import dplug.client.midi : MidiMessage, MidiStatus;
import mir.math : log2, exp2, fastmath, PI;

import synth2.waveform : Waveform, WaveformRange;
import synth2.voice : VoiceStatus;

@safe nothrow @nogc:

/// Converts MIDI velocity to gain.
/// Params:
///   velocity = MIDI velocity [0, 127].
///   sensitivity = gain sensitivity.
///   bias = gain bias.
/// Returns: Maps 0 to 127 into [0, 1] level with affine transformation.
float velocityToLevel(
    float velocity, float sensitivity = 1.0, float bias = 0.1) @fastmath pure {
  assert(0 <= velocity && velocity <= 127);
  return (velocity / 127f - bias) * sensitivity + bias;
}

/// Converts MIDI note to frequency.
/// Params:
///   note = MIDI note number [0, 127].
/// Returns: frequency [Hz].
float convertMIDINoteToFrequency(float note) @fastmath pure {
    return 440.0f * exp2((note - 69.0f) / 12.0f);
}

/// Polyphonic oscillator that generates WAV samples by given params and midi.
struct Oscillator
{
 public:
  @safe @nogc nothrow @fastmath:

  // Setters
  void setInitialPhase(float value) pure {
    _initialPhase = value;
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
    _velocitySense = value;
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
    _noteDetune = val;
  }

  /// Syncronize osc phase to the given src osc phase.
  /// Params:
  ///   src = modulating osc.
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

  /// Infinite range method.
  enum empty = false;

  /// Returns: sum of amplitudes of _waves at the current phase.
  float front() const pure {
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
        _waves[i].freq = convertMIDINoteToFrequency(_note(v));
      }
    }
  }

  /// Returns: true if any voices are playing.
  bool isPlaying() const pure {
    foreach (ref v; _voices) {
      if (v.isPlaying) return true;
    }
    return false;
  }

  /// Returns: the waveform object used last.
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
  float _note(const ref VoiceStatus v) const pure {
    return (_noteTrack ? v.note : 69.0f) + _noteDiff + _noteDetune
        + _pitchBend * _pitchBendWidth;
  }

  size_t _newVoiceId() const pure {
    foreach (i, ref v; _voices) {
      if (!v.isPlaying) {
        return i;
      }
    }
    return (_lastUsedId + 1) % _voices.length;
  }

  void markNoteOn(MidiMessage midi) pure @system {
    const i = _newVoiceId;
    const level =  velocityToLevel(midi.noteVelocity(), _velocitySense);
    _voices[i].play(midi.noteNumber(), level);
    if (_initialPhase != -PI)
      _waves[i].phase = _initialPhase;
    _lastUsedId = i;
  }

  void markNoteOff(int note) pure {
    foreach (ref v; _voices) {
      v.stop(note);
    }
  }

  inout(VoiceStatus)[] _voices() inout pure return {
    return _voicesArr[0 .. _maxVoices];
  }

  inout(WaveformRange)[] _waves() inout pure return {
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
