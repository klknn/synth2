/**
Waveform module.

Copyright: klknn 2021.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module synth2.waveform;

import mir.random : rand;
import mir.random.engine.xoshiro : Xoshiro128StarStar_32;
import mir.math : sin, PI, fmin, fastmath;

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
  float phase = 0;  // [0 .. 2 * PI]
  float normalized = false;
  float sampleRate = 44100;
  float pulseWidth = 0.5;
  Waveform waveform = Waveform.sine;
  static rng = Xoshiro128StarStar_32(0u);

  @safe nothrow @nogc @fastmath:

  enum empty = false;

  float front() const {
    final switch (this.waveform) {
      case Waveform.saw:
        return 1.0 - this.phase / (2 * PI);
      case Waveform.sine:
        return sin(this.phase);
      case Waveform.pulse:
        return this.phase <= this.pulseWidth * 2 * PI ? 1f : -1f;
      case Waveform.triangle:
        return 2f * fmin(this.phase, 2 * PI - this.phase) / PI - 1f;
      case Waveform.noise:
        return rand!float(this.rng);
    }
  }

  pure void popFront(long n = 1) {
    this.phase += this.freq * 2 * PI / this.sampleRate * n;
    this.normalized = false;
    if (this.phase >= 2 * PI) {
      this.phase %= 2 * PI;
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
    assert(0 <= w.phase && w.phase <= 2 * PI);
    w.popFront();
  }
}
