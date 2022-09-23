module synth2.random;

@nogc nothrow @safe pure
uint rotl(const uint x, int k) {
  return (x << k) | (x >> (32 - k));
}

// Based on https://prng.di.unimi.it/xoshiro128plus.c
struct Xorshiro128Plus {
  @nogc nothrow pure @safe:

  uint[4] s = [1];

  uint front() const {
    assert(!(s[0] == 0 && s[1] == 0 && s[2] == 0 && s[3] == 0));
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
}
