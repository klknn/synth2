/**
   Synth2 modulated filters.

   Copyright: klknn 2021.
   License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module synth2.modfilter;

import dplug.client.midi;
import mir.math.common : fmin, fmax, fastmath;

import synth2.envelope;
import synth2.filter;

/// Filter with MIDI and ADSR modulation.
struct ModFilter {
  /// Filter to be modurated.
  Filter filter;

  /// Modulating envelope.
  ADSR envelope;

  alias filter this;

  /// Use MIDI velocity for scaling the envelope. 
  bool useVelocity = false;

  /// Constant scaling factor for the envelope.
  float envAmount = 0;

  /// Constant scaling factor for MIDI frequency.
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
    this.envelope.setSampleRate(sampleRate);
    this.cutoffDiff = 0;
  }

  void setCutoffDiff(float diff) {
    this.cutoffDiff = diff;
  }

  /// Increments envlope timestamp.
  void popFront() {
    const cutoff = fmax(0f, fmin(1f, this.cutoff + this.cutoffDiff + this.track +
                                 this.velocity * this.envelope.front));
    this.filter.setParams(this.kind, cutoff, this.q);
    this.envelope.popFront();
  }

  @system void setMidi(MidiMessage msg) {
    if (msg.isNoteOn) {
      this.velocity = this.envAmount *
                      (this.useVelocity ? msg.noteVelocity / 127 : 1);
      this.track = this.trackAmount * msg.noteNumber / 127;
    }
    this.envelope.setMidi(msg);
  }

 private:
  // filter states
  float cutoff = 0;
  float cutoffDiff = 0;
  float q = 0;
  FilterKind kind;
  float velocity = 1;
  float track = 0;
}
