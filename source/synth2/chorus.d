module synth2.chorus;

import dplug.client.client : TimeInfo;

import synth2.delay : Delay, DelayKind;
import synth2.lfo : LFO, Multiplier;
import synth2.waveform : Waveform;


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

  float[2] apply(float[2] x...) {
    auto msecsMod = _msecs + _lfo.front * _depth;
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

  static immutable offsetMSecs = [12.5, 26.4, 18.4, 22.4];

  void setSampleRate(float sampleRate) {
    foreach (ref c; _chorus) {
      c.setSampleRate(sampleRate);
    }
  }

  void setParams(int numActive, float msecs, float feedback,
                 float depth, float rate) {
    _numActive = numActive;
    foreach (i, ref c; _chorus) {
      c.setParams(msecs + offsetMSecs[i], feedback, depth, rate);
    }
  }

  float[2] apply(float[2] x...) {
    float[2] y;
    y[] = 0;
    foreach (i; 0 .. _numActive) {
      y[] += _chorus[i].apply(x)[];
    }
    y[] /= _numActive;
    return y;
  }

 private:
  int _numActive;
  Chorus[4] _chorus;
}
