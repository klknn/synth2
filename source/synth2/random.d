module synth2.random;

@nogc nothrow @safe pure
uint rotl(const uint x, int k) {
  return (x << k) | (x >> (32 - k));
}

@nogc nothrow @safe pure
ulong splitmix64(ulong x) {
  ulong z = (x += 0x9e3779b97f4a7c15);
  z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9;
  z = (z ^ (z >> 27)) * 0x94d049bb133111eb;
  return z ^ (z >> 31);
}

// Based on https://prng.di.unimi.it/xoshiro128plus.c
struct Xorshiro128Plus {
  @nogc nothrow pure @safe:

  this(ulong seed) {
    s[0] = cast(uint) seed;
    s[1] = seed >> 32;

    ulong sp = splitmix64(seed);
    s[2] = cast(uint) sp;
    s[3] = sp >> 32;

    assert(!(s[0] == 0 && s[1] == 0 && s[2] == 0 && s[3] == 0));
  }

  uint front() const {
    return s[0] + s[3];
  }

  void popFront() {
    const uint t = s[1] << 9;

    s[2] ^= s[0];
    s[3] ^= s[1];
    s[1] ^= s[2];
    s[0] ^= s[3];

    s[2] ^= t;

    s[3] = rotl(s[3], 11);
  }

  /* This is the jump function for the generator. It is equivalent
     to 2^64 calls to next(); it can be used to generate 2^64
     non-overlapping subsequences for parallel computations. */
  void jump() {
    static immutable uint[] JUMP = [0x8764000b, 0xf542d2d3, 0x6fa035c3, 0x77f2db5b];

    uint s0 = 0;
    uint s1 = 0;
    uint s2 = 0;
    uint s3 = 0;
    foreach (J; JUMP) {
      for(int b = 0; b < 32; b++) {
        if (J & 1u << b) {
          s0 ^= s[0];
          s1 ^= s[1];
          s2 ^= s[2];
          s3 ^= s[3];
        }
        popFront();
      }
    }
    s[0] = s0;
    s[1] = s1;
    s[2] = s2;
    s[3] = s3;
  }

private:
  uint[4] s = [1, 2, 3, 4];
}
