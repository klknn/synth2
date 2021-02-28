/**
   Synth2 modulated filters.

   Copyright: klknn 2021.
   License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module synth2.modfilter;

import dplug.client.midi;
import mir.math.common : fmin, fastmath;

import synth2.envelope;
import synth2.filter;

/// Filter with MIDI and ADSR modulation.
struct ModFilter {
  Filter filter;
  ADSR envelope;
  alias filter this;

  bool useVelocity = false;
  float envAmount = 0;
  float trackAmount = 0;

  @nogc nothrow pure @safe @fastmath:

  void setParams(FilterKind kind, float freqPercent, float q) {
    this.cutoff = freqPercent;
    this.q = q;
    this.kind = kind;
    this.filter.setParams(this.kind, this.cutoff, this.q);
  }

  void setSampleRate(float sampleRate) {
    this.filter.setSampleRate(sampleRate);
    nplay = 0;
  }

  void popFront() {
    const cutoff = fmin(1f, this.cutoff + this.track +
                        this.velocity * this.envelope.front);
    this.filter.setParams(this.kind, cutoff, this.q);
    this.envelope.popFront();
  }

  @system void setMidi(MidiMessage msg) {
    if (msg.isNoteOn) {
      ++nplay;
      if (nplay == 1) this.envelope.attack();
      this.velocity = this.envAmount *
                      (this.useVelocity ? msg.noteVelocity / 127 : 1);
      this.track = this.trackAmount * msg.noteNumber / 127;
    }
    if (msg.isNoteOff) {
      --nplay;
      if (nplay == 0) this.envelope.release();
    }
  }

 private:
  // filter states
  int nplay = 0;
  float cutoff = 0;
  float q = 0;
  FilterKind kind;
  float velocity = 1;
  float track = 1;
}