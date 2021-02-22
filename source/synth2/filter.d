/// Filter constants are based on these books
/// https://cs.gmu.edu/~sean/book/synthesis/Synthesis.pdf
/// https://www.discodsp.net/VAFilterDesign_2.1.0.pdf
module synth2.filter;

import mir.math : approxEqual, PI, SQRT2;

@nogc nothrow @safe pure:

enum FilterKind {
  lowpass,
  highpass,
  bandpass,
  notch,
}

static immutable filterNames = [__traits(allMembers, FilterKind)];

struct Filter2Pole {
  enum nFIR = 3;
  enum nIIR = 2;

  @nogc nothrow @safe pure:
  
  void clear() {
    x[] = 0f;
    y[] = 0f;
  }
  
  float apply(float input) {
    // TODO: use ring buffer
    static foreach_reverse (i; 1 .. nFIR) {
      x[i] = x[i - 1];
    }
    x[0] = input;

    float output = 0;
    static foreach (i; 0 .. nFIR) {
      output += b[i] * x[i];
    }
    static foreach (i; 0 .. nIIR) {
      output -= a[i] * y[i];
    }

    static foreach_reverse (i; 1 .. nIIR) {
      y[i] = y[i - 1];
    }
    y[0] = output;
    return output;
  }

  void setSampleRate(float sampleRate) {
    sampleRate = sampleRate;
    this.clear();
  }

  void setParams(FilterKind kind, float freqPercent, float q) {
    q += 1f / SQRT2;
    float t =1f / sampleRate;
    float w = 2f * PI * freqPercent / 100f * sampleRate;
    float j = 4f * q + 2f * w * t + w * w * q * t * t;

    if (kind == FilterKind.lowpass) {
      b[0] = 1f / j * w * w * q * t * t;
      b[1] = 1f / j * 2f * w * w * q * t * t;
      b[2] = 1f / j * w * w * q * t * t;
      a[0] = 1f / j * (-8f * q + 2f * w * w * q * t * t);
      a[1] = 1f / j * (4f * q - 2f * w * t + w * w * q * t * t);
    }
    else {
      assert(false, "not implemented");
    }
  }

 private:
  float sampleRate = 44100;
  // filter and prev inputs
  float[nFIR] b, x;
  // filter and prev outputs
  float[nIIR] a, y;
}

unittest {
  Filter2Pole f;
  f.setSampleRate(20);
  f.setParams(FilterKind.lowpass, 5, 2);

  // with padding
  auto y0 = f.apply(0.1);
  assert(approxEqual(y0, f.b[0] * 0.1));

  auto y1 = f.apply(0.2);
  assert(approxEqual(y1, f.b[0] * 0.2 + f.b[1] * 0.1 - f.a[0] * y0));

  auto y2 = f.apply(0.3);
  assert(approxEqual(y2,
                     f.b[0] * 0.3 + f.b[1] * 0.2 + f.b[0] * 0.1
                     -f.a[0] * y1 - f.a[1] * y0));

  // without padding
  auto y3 = f.apply(0.4);
  assert(approxEqual(y3,
                     f.b[0] * 0.4 + f.b[1] * 0.3 + f.b[0] * 0.2
                     -f.a[0] * y2 - f.a[1] * y1));
}
