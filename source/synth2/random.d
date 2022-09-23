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
     to 2^64 calls to popFront(); it can be used to generate 2^64
     non-overlapping subsequences for parallel computations. */
  void jump() {
    _jump!([0x8764000b, 0xf542d2d3, 0x6fa035c3, 0x77f2db5b]);
  }

  /* This is the long-jump function for the generator. It is equivalent to
     2^96 calls to popFront(); it can be used to generate 2^32 starting points,
     from each of which jump() will generate 2^32 non-overlapping
     subsequences for parallel distributed computations. */
  void longJump() {
    _jump!([0xb523952e, 0x0b6f099f, 0xccf5a0ef, 0x1c580662]);
  }

private:

  void _jump(const uint[4] JUMP)() {
    uint[4] a;
    foreach (j; JUMP) {
      foreach (b; 0 .. 32) {
        if (j & 1u << b) {
          a[] ^= s[];
        }
        popFront();
      }
    }
    s[] = a[];
  }

  uint[4] s = [0, 0, cast(uint) splitmix64(0), splitmix64(0) >> 32];
}

@nogc nothrow pure @safe
unittest {
  Xorshiro128Plus rng0, rng1, rng2;
  assert(rng0.s == rng1.s, "initial seeds should be equal.");

  uint x0 = rng0.front();
  assert(x0 == rng1.front(), "front should be the same if seeds are equal.");

  rng0.popFront();
  assert(rng0.front != x0, "front should be changed by popFront.");

  rng1.popFront();
  assert(rng0.front == rng1.front(), "popFront() should be reproducible");

  rng1.jump();
  assert(rng0.front != rng1.front, "jump() should mutate front.");

  rng0.jump();
  assert(rng0.front == rng1.front,
         "Both rng0 and rng1 call 1 jump + 1 popFront in total.");

  rng2.popFront();
  rng2.jump();
  rng2.longJump();
  assert(rng0.front != rng2.front, "longJump() should mutate front.");

  rng0.longJump();
  assert(rng0.front == rng2.front,
         "Both rng0 and rng2 call 1 longJump + 1 jump + 1 popFront in total.");


  assert(Xorshiro128Plus.init.s == Xorshiro128Plus(0).s,
         "Zero seeded states should be equal to the default-initialized ones.");

  assert(Xorshiro128Plus.init.s != Xorshiro128Plus(1).s,
         "Non-zero states should be different from the default-initialized ones.");
}
