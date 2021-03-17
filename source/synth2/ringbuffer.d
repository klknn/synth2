module synth2.ringbuffer;

import core.memory : pureFree, pureRealloc;

/// @nogc/nothrow ring buffer.
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
