module synth2.envelope;

enum Stage {
  attack,
  decay,
  sustain,
  release,
  done,
}

/// Attack, Decay, Sustain, Release.
struct ADSR {
  // public mutable fields
  float attackTime = 0;
  float decayTime = 0;
  float sustainLevel = 1;
  float releaseTime = 0;
  float frameWidth = 1.0 / 44100;

  @nogc nothrow @safe pure:
  
  void attack() {
    this._stage = Stage.attack;
    this._stageTime = 0;
  }

  void release() {
    this._releaseLevel = this.front;
    this._stage = Stage.release;
    this._stageTime = 0;
  }

  bool empty() const { return this._stage == Stage.done; }

  /// Returns an amplitude of the linear envelope.
  float front() const {
    final switch (this._stage) {
      case Stage.attack:
        return this.attackTime == 0 ? 1 : (this._stageTime / this.attackTime);
      case Stage.decay:
        return this.decayTime == 0
            ? 1
            : (this._stageTime * (this.sustainLevel -  1f) /  this.decayTime + 1f);
      case Stage.sustain:
        return this.sustainLevel;
      case Stage.release:
        import std.math : isNaN;
        assert(!isNaN(this._releaseLevel), "invalid release level.");
        return this.releaseTime == 0 ? 0f
            : (-this._stageTime * this._releaseLevel / this.releaseTime
               + this._releaseLevel);
      case Stage.done:
        return 0f;
    }
  }

  /// Update status if the stage is in (attack, decay, release).
  void popFront() {
    final switch (this._stage) {
      case Stage.attack:
        this._stageTime += this.frameWidth;
        if (this._stageTime >= this.attackTime) {
          this._stage = Stage.decay;
          this._stageTime = 0;
        }
        return;
      case Stage.decay:
        this._stageTime += this.frameWidth;
        if (this._stageTime >= this.decayTime) {
          this._stage = Stage.sustain;
          this._stageTime = 0;
        }
        return;
      case Stage.sustain:
        return; // do nothing.
      case Stage.release:
        this._stageTime += this.frameWidth;
        if (this._stageTime >= this.releaseTime) {
          this._stage = Stage.done;
          this._stageTime = 0;
        }
        return;
      case Stage.done:
        return;  // do nothing.
    }
  }

 private:
  Stage _stage = Stage.attack;
  float _stageTime = 0;
  float _releaseLevel;
}

/// Test ADSR.
@nogc nothrow pure @safe
unittest {
  ADSR env;
  env.attackTime = 5;
  env.decayTime = 5;
  env.sustainLevel = 0.5;
  env.releaseTime = 20;
  env.frameWidth = 1;

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
  }
}
