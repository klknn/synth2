module synth2.delay;

import core.memory : pureFree, pureRealloc;
import std.math : abs;

enum maxDelaySec = 10.0f;

struct RingBuffer(T) {
  void recalloc(size_t n) {
    if (n == _capacity) return;
    _ptr = cast(T*) pureRealloc(_ptr, n * T.sizeof);
    assert(_ptr, "realloc failed");
    _capacity = n;
    this.clear();
  }

  void clear() {
    _ptr[0 .. _capacity] = 0;
  }

  ~this() { pureFree(_ptr); }

  T front() const { return _ptr[_front_idx]; }

  void enqueue(T val) {
    _ptr[_back_idx] = val;
    _back_idx = (_back_idx + 1) % _capacity;
    _front_idx = (_front_idx + 1) % _capacity;
  }

  /// Resizes the buffer. Initializes values to 0 if newlen > capacity.
  void resize(size_t newlen) {
    assert(newlen <= _capacity, "capacity exceeded");
    // Ignore newlen in release mode.
    if (newlen > _capacity) {
      // recalloc(newlen);
      newlen = _capacity;
    }
    _front_idx = newlen < _back_idx
        ? _back_idx - newlen
        : _capacity - (newlen - _back_idx);
  }

  size_t length() const {
    return _front_idx < _back_idx
        ? _back_idx - _front_idx
        : _capacity + _back_idx - _front_idx;
  }

 private:
  T* _ptr;
  size_t _capacity, _front_idx, _back_idx;
}

@nogc nothrow pure
unittest {
  RingBuffer!float buf;
  buf.recalloc(2);
  buf.resize(2);
  assert(buf.length == 2);
  assert(buf.front == 0);

  buf.enqueue(1);
  assert(buf.front == 0);
  assert(buf.length == 2);

  buf.enqueue(2);
  assert(buf.front == 1);
  assert(buf.length == 2);

  // resize shorter
  buf.resize(1);
  assert(buf.length == 1);
  assert(buf.front == 2);

  // resize longer
  buf.resize(2);
  assert(buf.length == 2);
  assert(buf.front == 1);  // previous front
}

enum DelayKind {
  st, // normal stereo
  x,  // cross feedback
  pp, // pingpong
}

static immutable delayNames = [__traits(allMembers, DelayKind)];

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
  float _sampleRate = 44100;
}

unittest {
  Delay dly;
  dly.setSampleRate(44100);
  dly.setParams(DelayKind.st, 0.5, 0, 0);
  assert(dly.apply(1f, 2f) == [0f, 0f]);

  dly.setParams(DelayKind.pp, 0.5, 0, 0);
  assert(dly.apply(1f, 2f) == [0f, 0f]);

  dly.setParams(DelayKind.x, 0.5, 0, 0);
  assert(dly.apply(1f, 2f) == [0f, 0f]);
}
