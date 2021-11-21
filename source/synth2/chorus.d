module synth2.chorus;

import dplug.client.client : TimeInfo;

import synth2.delay : Delay, DelayKind;
import synth2.lfo : LFO, Multiplier;
import synth2.waveform : Waveform;


/// Chorus adds short modurated delay sounds.
struct Chorus {
  @nogc nothrow:

  void setSampleRate(float sampleRate) {
    _lfo.setSampleRate(sampleRate);
    _delay.setSampleRate(sampleRate);
  }

  void setParams(float msecs, float feedback, float depth, float rate) {
    _depth = depth;
    _msecs = msecs;
    _feedback = feedback;
    _lfo.setParams(Waveform.sine, false, rate / 10, Multiplier.none, TimeInfo.init);
  }

  /// Applies chorus effect.
  /// Params:
  ///   x = dry stereo input.
  /// Returns:
  ///   wet modulated chorus output.
  float[2] apply(float[2] x...) {
    auto msecsMod = _msecs + (_lfo.front + 1) * _depth;
    _lfo.popFront();
    _delay.setParams(DelayKind.st, msecsMod * 1e-3, 0, _feedback);
    return _delay.apply(x);
  }

 private:
  float _depth, _msecs, _feedback;
  Delay _delay;
  LFO _lfo;
}


struct MultiChorus {
  @nogc nothrow:

  static immutable offsetMSecs = [0.55, 0.64, 12.5, 26.4, 18.4];

  void setSampleRate(float sampleRate) {
    foreach (ref c; _chorus) {
      c.setSampleRate(sampleRate);
    }
  }

  void setParams(int numActive, float width,
                 float msecs, float feedback, float depth, float rate) {
    _numActive = numActive;
    _width = width;
    foreach (i, ref c; _chorus) {
      c.setParams(msecs + offsetMSecs[i], feedback, depth, rate);
    }
  }

  float[2] apply(float[2] x...) {
    float[2] y;
    y[] = 0;
    if (_width == 0 || _numActive == 1) {
      foreach (i; 0 .. _numActive) {
        y[] += _chorus[i].apply(x)[];
      }
    }
    // Wide stereo panning.
    else {
      const width = _width / 2 + 0.5;  // range [0.5, 1.0]
      if (_numActive >= 2) {
        const c0 = _chorus[0].apply(x);
        y[0] += width * c0[0];
        y[1] += (1 - width) * c0[1];
        const c1 = _chorus[1].apply(x);
        y[0] += (1 - width) * c1[0];
        y[1] += width * c1[1];
      }
      if (_numActive == 3) {
        y[] += _chorus[2].apply(x)[];
      }
      if (_numActive == 4) {
        const halfWidth = _width / 2 + 0.5;  // range [0.5, 0.75]
        const c2 = _chorus[2].apply(x);
        y[0] += halfWidth * c2[0];
        y[1] += (1 - halfWidth) * c2[1];
        const c3 = _chorus[3].apply(x);
        y[0] += (1 - halfWidth) * c3[0];
        y[1] += halfWidth * c3[1];
      }
    }
    y[] /= _numActive;
    return y;
  }

 private:
  float _width;
  int _numActive;
  Chorus[4] _chorus;
}
