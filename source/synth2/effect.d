/**
Effect module.

Copyright: klknn 2021.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module synth2.effect;

import std.math : tanh, sgn;
import std.traits : EnumMembers;

import dplug.core.math : convertLinearGainToDecibel, convertDecibelToLinearGain;
import dplug.core.nogc : mallocNew, destroyFree;
import mir.math : powi, exp, fabs, PI, log2, floor;

import synth2.waveform : Waveform, WaveformRange;
import synth2.filter : Filter, FilterKind, AllPassFilter;

/// Base effect class.
interface IEffect {
  nothrow @nogc:
  /// Sets the sample rate from host.
  void setSampleRate(float sampleRate);

  /// Sets parameters for the effect, ctrls are in [0, 1].
  void setParams(float ctrl1, float ctrl2);

  /// Applies the effect configured by ctrl1/2.
  float apply(float x);
}

/// Base distortion with LPF.
abstract class BaseDistortion : IEffect {
 public:
  nothrow @nogc @safe pure:

  override void setSampleRate(float sampleRate) {
    _lpf.setSampleRate(sampleRate);
  }

  /// Sets parameters for the effect.
  /// Params:
  ///   ctrl1 = distortion gain.
  ///   ctrl2 = LPF cutoff.
  override void setParams(float ctrl1, float ctrl2) {
    _gain = ctrl1 * 10;
    _lpf.setParams(FilterKind.LP12, ctrl2, 0);
  }

  override float apply(float x) {
    return _lpf.apply(distort(_gain * x) / 10);
  }

  /// Applies distortion.
  abstract float distort(float x) const;
 private:
  float _gain;
  Filter _lpf;
}

class AnalogDistortionV1 : BaseDistortion {
 public:
  nothrow @nogc @safe pure
  override float distort(float x) const {
    return fabs(tanh(x)) * 2f - 1f;
  }
}

class AnalogDistortionV2 : BaseDistortion {
 public:
  nothrow @nogc @safe pure
  override float distort(float x) const {
    return tanh(x);
  }
}

class DigitalDistortion : BaseDistortion {
 public:
  nothrow @nogc @safe pure
  override float distort(float x) const {
    return sgn(x) * (1 - exp(-fabs(x)));
  }
}

class Resampler : IEffect {
 public:
  nothrow @nogc @safe pure:

  override void setSampleRate(float sampleRate) {
    _sampleRate = sampleRate;
    _qx = 0;
    _frame = 0;
  }

  override void setParams(float ctrl1, float ctrl2) {
    // Resample into sampleRate / 1000 .. sampleRate
    _resampleFrames = cast(int) ((1 - ctrl1) * _sampleRate / 1000) + 1;
    // Scale into 1 .. 24bit
    _nbit = cast(int) (ctrl2 * 23 + 1);
  }

  override float apply(float x) {
    if (_frame == 0) {
      // Consider better coding, e.g., mu-low?
      _qx = floor(x * _nbit) / _nbit;
    }
    _frame = (_frame + 1) % _resampleFrames;
    return _qx;
  }

 private:
  float _sampleRate;
  // ctrls
  int _resampleFrames;
  int _nbit;
  // states
  float _qx;
  int _frame;
}

class RingMod : IEffect {
 public:
  nothrow @nogc @safe:

  pure override void setSampleRate(float sampleRate) {
    _wave.sampleRate = sampleRate;
  }

  pure override void setParams(float ctrl1, float ctrl2) {
    _wave.freq = log2(ctrl1 + 1) * _wave.sampleRate / 10;
  }

  override float apply(float x) @system {
    scope (exit) _wave.popFront();
    return _wave.front * x;
  }

 private:
  WaveformRange _wave = { waveform: Waveform.sine };
}

class Compressor : IEffect {
 public:
  nothrow @nogc @safe pure:

  override void setSampleRate(float sampleRate) {
    _avg = 0;
  }

  override void setParams(float ctrl1, float ctrl2) {
    _threshold = ctrl1; // convertLinearGainToDecibel(ctrl1);
    _attack = ctrl2;
  }

  override float apply(float x) {
    const absx = fabs(x); // convertLinearGainToDecibel(fabs(x));
    _avg = (1 - _attack) * absx + _attack * _avg;
    if (_threshold < _avg && _threshold < absx) {
      return sgn(x) * // convertDecibelToLinearGain
          (_threshold + (absx - _threshold) / _ratio);
    }
    return x;
  }

 private:
  float _avg;
  float _threshold;
  float _sampleRate;
  float _ratio = 5;
  float _attack;
}

/// Phase effect. WIP TODO: add LFOs.
/// Params:
///   n = number of the phase effects.
/// See_also:
///   https://ccrma.stanford.edu/realsimple/DelayVar/Phasing_First_Order_Allpass_Filters.html
class Phaser(size_t n) : IEffect {
 public:
  nothrow @nogc:
  /// Sets the sample rate from host.
  /// Params:
  ///   sampleRate = sampling rate.
  void setSampleRate(float sampleRate) {
    foreach (ref f; _filters) {
      f.setSampleRate(sampleRate);
    }
  }

  /// Sets parameters for the effect, ctrls are in [0, 1].
  /// Params:
  ///   ctrl1 = all-pass filter cutoff.
  ///   ctrl2 = mix balance btw dry and phase shifted signals.
  void setParams(float ctrl1, float ctrl2) {
    foreach (ref f; _filters) {
      f.g = ctrl1;
    }
    _mix = ctrl2;
  }

  /// Applies the effect configured by ctrl1/2.
  /// Params:
  ///   x = the current mono input.
  /// Returns: output with modulated phase.
  float apply(float x) {
    float y = x;
    foreach (ref f; _filters) {
      y = f.apply(y);
    }
    return _mix * y + (1 - _mix) * x;
  }

 private:
  AllPassFilter[n] _filters;
  float _mix;
}

/// Effect ids to select one in MultiEffect._effect;
enum EffectKind {
  ad1,
  ad2,
  dd,
  deci,
  ring,
  comp,
  ph3,
}

static immutable effectNames = [__traits(allMembers, EffectKind)];

/// Multi effect class for the plugin client.
class MultiEffect : IEffect {
 public:
  nothrow @nogc:

  this() {
    _effects[EffectKind.ad1] = mallocNew!AnalogDistortionV1;
    _effects[EffectKind.ad2] = mallocNew!AnalogDistortionV2;
    _effects[EffectKind.dd] = mallocNew!DigitalDistortion;
    _effects[EffectKind.deci] = mallocNew!Resampler;
    _effects[EffectKind.comp] = mallocNew!Compressor;
    _effects[EffectKind.ring] = mallocNew!RingMod;
    _effects[EffectKind.ph3] = mallocNew!(Phaser!3);
  }

  ~this() {
    foreach (e; _effects) {
      destroyFree(e);
    }
  }

  void setEffectKind(EffectKind kind) {
    _current = kind;
  }

  override void setSampleRate(float sampleRate) {
    foreach (IEffect e; _effects) {
      e.setSampleRate(sampleRate);
    }
  }

  override void setParams(float ctrl1, float ctrl2) {
    _effects[_current].setParams(ctrl1, ctrl2);
  }

  override float apply(float x) {
    return _effects[_current].apply(x);
  }

 private:
  EffectKind _current;
  IEffect[EnumMembers!EffectKind.length] _effects;
}

@nogc nothrow @system
unittest {
  import std.math : isNaN;

  MultiEffect efx = mallocNew!MultiEffect;
  scope (exit) destroyFree(efx);

  efx.setSampleRate(44_100);
  foreach (e; EnumMembers!EffectKind) {
    efx.setEffectKind(e);
    efx.setParams(0.5, 0.5);
    const y = efx.apply(0);
    assert(!y.isNaN);
    assert(-1 <= y && y <= 1);
  }
}
