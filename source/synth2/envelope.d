/**
   Synth2 ADSR envelope module.

   Copyright: klknn 2021.
   License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module synth2.envelope;

import std.math : isNaN;

import dplug.client.midi : MidiMessage;
import mir.math.common : fastmath;

/// Envelope stages.
enum Stage {
  attack,
  decay,
  sustain,
  release,
  done,
}

/// Attack, Decay, Sustain, Release.
struct ADSR {
  /// Attack time in #frames.
  float attackTime = 0;
  /// Decay time in #frames.
  float decayTime = 0;
  /// Sustain level within [0, 1].
  float sustainLevel = 1;
  /// Release time in #frames.
  float releaseTime = 0;

  @nogc nothrow @safe pure @fastmath:

  /// Triggers the atack stage.
  void attack() {
    _stage = Stage.attack;
    _stageTime = 0;
  }

  /// Triggers the release stage.
  void release() {
    _releaseLevel = this.front;
    _stage = Stage.release;
    _stageTime = 0;
  }

  void setSampleRate(float sampleRate) {
    _frameWidth = 1f / sampleRate;
    _stage = Stage.done;
    _stageTime = 0;
    _nplay = 0;
  }

  /// Returns: true if envelope was ended.
  bool empty() const { return _stage == Stage.done; }

  /// Returns: an amplitude of the linear envelope.
  float front() const {
    final switch (_stage) {
      case Stage.attack:
        return this.attackTime == 0 ? 1 : (_stageTime / this.attackTime);
      case Stage.decay:
        return this.decayTime == 0
            ? 1 : (_stageTime * (this.sustainLevel -  1f) /  this.decayTime + 1f);
      case Stage.sustain:
        return this.sustainLevel;
      case Stage.release:
        assert(!isNaN(_releaseLevel), "invalid release level.");
        return this.releaseTime == 0 ? 0f
            : (-_stageTime * _releaseLevel / this.releaseTime
               + _releaseLevel);
      case Stage.done:
        return 0f;
    }
  }

  /// Update status if the stage is in (attack, decay, release).
  void popFront() {
    final switch (_stage) {
      case Stage.attack:
        _stageTime += _frameWidth;
        if (_stageTime >= this.attackTime) {
          _stage = Stage.decay;
          _stageTime = 0;
        }
        return;
      case Stage.decay:
        _stageTime += _frameWidth;
        if (_stageTime >= this.decayTime) {
          _stage = Stage.sustain;
          _stageTime = 0;
        }
        return;
      case Stage.sustain:
        return; // do nothing.
      case Stage.release:
        _stageTime += _frameWidth;
        if (_stageTime >= this.releaseTime) {
          _stage = Stage.done;
          _stageTime = 0;
        }
        return;
      case Stage.done:
        return;  // do nothing.
    }
  }

  @system void setMidi(MidiMessage msg) {
    if (msg.isNoteOn) {
      if (_nplay == 0) this.attack();
      ++_nplay;
    }
    if (msg.isNoteOff) {
      --_nplay;
      if (_nplay == 0) this.release();
    }
  }

 private:
  Stage _stage = Stage.done;
  float _frameWidth = 1.0 / 44_100;
  float _stageTime = 0;
  float _releaseLevel;
  int _nplay = 0;
}

/// Test ADSR.
@nogc nothrow pure @safe
unittest {
  ADSR env;
  env.attackTime = 5;
  env.decayTime = 5;
  env.sustainLevel = 0.5;
  env.releaseTime = 20;
  env._frameWidth = 1;

  foreach (_; 0 .. 2) {
    env.attack();
    foreach (i; 0 .. env.attackTime) {
      assert(env._stage == Stage.attack);
      env.popFront();
    }
    foreach (i; 0 .. env.decayTime) {
      assert(env._stage == Stage.decay);
      env.popFront();
    }
    assert(env._stage == Stage.sustain);
    env.release();
    // foreach does not mutate `env`.
    foreach (amp; env) {
      assert(env._stage == Stage.release);
    }
    foreach (i; 0 .. env.releaseTime) {
      assert(env._stage == Stage.release);
      env.popFront();
    }
    assert(env._stage == Stage.done);
    assert(env.empty);
    assert(env.front == 0);
  }
}
