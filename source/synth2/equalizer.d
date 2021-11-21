/**
   Synth2 equalizer.

   Copyright: klknn 2021.
   License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module synth2.equalizer;

import mir.math.common : fabs, log, fmax, exp;

import synth2.filter : Filter, FilterKind;

private enum bias = 1e-6;

/// tone [0, 1] -> [bias, 1] via log curve
private float logTransform(float x) @nogc nothrow pure @safe {
  return exp(-(x + bias) * log(bias)) * bias;
}

/// Equalizer.
struct Equalizer {
  @nogc nothrow pure @safe:

  void setSampleRate(float sampleRate) {
    _bs.setSampleRate(sampleRate);
    _hp.setSampleRate(sampleRate);
    _lp.setSampleRate(sampleRate);
  }

  void setParams(float level, float freq, float q, float tone) {
    _level = level < 0 ? level : 10 * level;
    _bs.setParams(FilterKind.BP12, freq, q);
    _tone = tone;
    if (tone > 0) {
      _hp.setParams(FilterKind.HP12, logTransform(tone), 0);
    }
    if (tone < 0) {
      _lp.setParams(FilterKind.LP12, logTransform(1 + tone), 0);
    }
  }

  /// Applies equalizer.
  /// Params:
  ///   x = input wave frame.
  /// Returns: equalized output wave frame.
  float apply(float x) {
    if (_level != 0) {
      x += _level * _bs.apply(x);
    }
    if (_tone > 0) {
      return _hp.apply(x);
    }
    if (_tone < 0) {
      return _lp.apply(x);
    }
    return x;
  }

 private:
  float _level = 0;
  float _tone = 0;
  Filter _bs, _hp, _lp;
}
