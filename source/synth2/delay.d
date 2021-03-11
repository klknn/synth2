module synth2.delay;

import core.memory : pureFree, pureRealloc;
import std.math : abs;

enum maxDelaySec = 10.0f;

struct RingBuffer(T) {
  void recalloc(size_t n) {
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
    if (newlen > _capacity) {
      recalloc(newlen);
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
  buf.resize(4);
  assert(buf.length == 4);
  assert(buf.front == 0); // cleared
}

enum DelayKind {
  st, // normal stereo
  x,  // cross feedback
  pp, // pingpong
}

struct Delay {
  @nogc nothrow pure:

  void setSampleRate(float sampleRate) {
    _sampleRate = sampleRate;
    _buffer.resize(cast(size_t) sampleRate * 3);
  }

  void setParams(float delaySecs, float feedback) {
    const delayFrames = cast(size_t) (delaySecs * _sampleRate);
    _buffer.resize(delayFrames);
    _feedback = feedback;
  }

  float apply(float x) {
    auto y = _buffer.front;
    _buffer.enqueue((1f - _feedback) * x + _feedback * y);
    return y;
  }

 private:
  RingBuffer!float _buffer;
  float _feedback = 0;
  float _sampleRate = 44100;
}

// unittest {
//   Delay dly;
//   dly.setParams(1, 0.5);
//   assert(dly.apply(1) == 0);
// }
