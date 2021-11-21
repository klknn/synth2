module synth2.delay;

import synth2.ringbuffer : RingBuffer;

/// Maximum delay interval in seconds.
enum maxDelaySec = 10.0f;

/// Kind of delay stereo effects.
enum DelayKind {
  st, // normal stereo
  x,  // cross feedback
  pp, // pingpong
}

/// String names of delay kinds.
static immutable delayNames = [__traits(allMembers, DelayKind)];

/// Delay effect.
struct Delay {
  @nogc nothrow pure:

  void setSampleRate(float sampleRate) {
    _sampleRate = sampleRate;
    const maxFrames = cast(size_t) (sampleRate * maxDelaySec);
    foreach (ref b; _buffers) {
      b.recalloc(maxFrames);
    }
  }

  void setParams(DelayKind kind, float delaySecs, float spread, float feedback) {
    _kind = kind;
    _feedback = feedback;
    const delayFrames = cast(size_t) (delaySecs * _sampleRate);
    const spreadFrames = cast(size_t) (spread * _sampleRate);
    _buffers[0].resize(delayFrames + spreadFrames);
    _buffers[1].resize(
        cast(size_t) (delayFrames * (_kind == DelayKind.pp ? 1 : 1 / 1.5)));
  }

  /// Applies delay effect.
  /// Params:
  ///   x = dry stereo input.
  /// Returns:
  ///   wet delayed output.
  float[2] apply(float[2] x...) {
    float[2] y;
    y[0] = _buffers[0].front;
    y[1] = _buffers[1].front;
    size_t f0 = 0;
    size_t f1 = 1;
    if (_kind == DelayKind.x) {
      f0 = 1;
      f1 = 0;
    }
    _buffers[0].enqueue((1f - _feedback) * x[0] + _feedback * y[f0]);
    _buffers[1].enqueue((1f - _feedback) * x[1] + _feedback * y[f1]);
    return y;
  }

 private:
  DelayKind _kind;
  RingBuffer!float[2] _buffers;
  float _feedback = 0;
  float _sampleRate = 44_100;
}

unittest {
  Delay dly;
  dly.setSampleRate(44_100);
  dly.setParams(DelayKind.st, 0.5, 0, 0);
  assert(dly.apply(1f, 2f) == [0f, 0f]);

  dly.setParams(DelayKind.pp, 0.5, 0, 0);
  assert(dly.apply(1f, 2f) == [0f, 0f]);

  dly.setParams(DelayKind.x, 0.5, 0, 0);
  assert(dly.apply(1f, 2f) == [0f, 0f]);
}
