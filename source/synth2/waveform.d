/**
Waveform module.

Copyright: klknn 2021.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module synth2.waveform;

import mir.math : sin, PI, M_1_PI, M_2_PI, fmin, fastmath, fma;

import synth2.random : Xorshiro128Plus;

/// Waveform kind.
enum Waveform {
  sine,
  saw,
  pulse,
  triangle,
  noise,
}

/// String names of waveforms.
static immutable waveformNames = [__traits(allMembers, Waveform)];

/// Waveform range.
struct WaveformRange {
  @fastmath @safe nothrow @nogc pure:

  /// Infinite range method.
  enum empty = false;

  /// Returns: the current wave value.
  float front() const {
    final switch (this.waveform) {
      case Waveform.saw:
        return fma(- M_1_PI, this.phase, 1f);
      case Waveform.sine:
        return sin(this.phase);
      case Waveform.pulse:
        return this.phase <= this.pulseWidth * 2 * PI ? 1f : -1f;
      case Waveform.triangle:
        return fma(M_2_PI, fmin(this.phase, 2 * PI - this.phase), -1f);
      case Waveform.noise:
        return fma(2f / uint.max, cast(float) this.rng.front, - 1f);
    }
  }

  /// Increments timestamp of osc.
  /// Params:
  ///   n = #frames.
  void popFront(long n = 1) {
    if (this.waveform == Waveform.noise) {
      this.rng.popFront();
      return;
    }

    this.phase += this.freq * 2 * PI / this.sampleRate * n;
    this.normalized = false;
    if (this.phase >= 2 * PI) {
      this.phase %= 2 * PI;
      this.normalized = true;
    }
  }

  ///
  float freq = 440;
  ///
  float sampleRate = 44_100;
  ///
  Waveform waveform = Waveform.sine;
  ///
  float phase = 0;  // [0 .. 2 * PI]
  ///
  float normalized = false;
  ///
  float pulseWidth = 0.5;

 private:
  Xorshiro128Plus rng = Xorshiro128Plus(0);
}

///
@safe nothrow @nogc pure unittest {
  import std.range;
  assert(isInputRange!WaveformRange);
  assert(isInfinite!WaveformRange);

  WaveformRange w;
  w.waveform = Waveform.noise;
  foreach (_; 0 .. 10) {
    assert(-1 < w.front && w.front < 1);
    w.popFront();
  }
}
