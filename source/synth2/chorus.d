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
    _delay.setParams(DelayKind.st, _msecs * 1e-3, 0, _feedback);
    return _delay.apply(x);
  }

 private:
  float _depth, _msecs, _feedback;
  Delay _delay;
  LFO _lfo;
}
