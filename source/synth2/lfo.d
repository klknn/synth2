/**
   Synth2 LFO (low freq osc) module.

   Copyright: klknn 2021.
   License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module synth2.lfo;

import std.algorithm.comparison : min;
import std.math : approxEqual;
import std.traits : EnumMembers;

import dplug.client.client : TimeInfo;
import dplug.client.midi : MidiMessage;

import synth2.waveform : Waveform, WaveformRange;

/// Note duration relative to bars.
enum Bar {
  x32 = 32f,
  x16 = 16f,
  x8 = 8f,
  x4 = 4f,
  x2 = 2f,
  x1 = 1f,
  x1_2 = 1f / 2f,
  x1_4 = 1f / 4f,
  x1_8 = 1f / 8f,
  x1_16 = 1f / 16f,
  x1_32 = 1f / 32f,
}

/// Bar multiplier.
enum Multiplier {
  dot,
  none,
  tri,
}

static immutable multiplierNames = [__traits(allMembers, Multiplier)];
static immutable float[multiplierNames.length] mulToFloat = [
    Multiplier.dot: 1.5f, Multiplier.none: 1f, Multiplier.tri: 1f / 3 ];

struct Interval {
  Bar bar;
  Multiplier mul;

  @nogc nothrow pure @safe:

  float toFloat() const {
    return bar * mulToFloat[mul];
  }

  alias toFloat this;
}

@nogc nothrow pure @safe
unittest {
  assert(Interval(Bar.x1_8, Multiplier.none).toFloat == 1f / 8);
  assert(Interval(Bar.x1_8, Multiplier.dot).toFloat == 1f / 8 * 1.5);
  assert(approxEqual(Interval(Bar.x1_8, Multiplier.tri).toFloat, 1f / 8 / 3));
}

@nogc nothrow pure @safe
Bar toBar(float x) {
  assert(0 <= x && x <= 1);
  static immutable bars = [EnumMembers!Bar];
  return bars[cast(int) (x * ($ - 1))];
}

@nogc nothrow pure @safe
unittest {
  assert(1.toBar == Bar.x1_32);
  assert(0.5.toBar == Bar.x1);
  assert(0.toBar == Bar.x32);
}

/// Low freq osc.
struct LFO {
  @nogc nothrow @safe:

  void setSampleRate(float sampleRate) pure {
    _wave.sampleRate = sampleRate;
    _nplay = 0;
  }

  /// Sets LFO parameters.
  /// Params:
  ///   waveform = waveform type.
  ///   sync = flag to sync tempo.
  ///   normalizedSpeed = [0, 1] value to control speed.
  ///   mult = duration multiplier for sync.
  ///   tinfo = info on bpm etc.
  void setParams(Waveform waveform, bool sync, float normalizedSpeed,
                 Multiplier mult, TimeInfo tinfo) pure {
    _wave.waveform = waveform;
    if (sync) {
      // BPM / 60sec (beat per sec) * 4 (bar per sec) / bar-length-scale
      _wave.freq = cast(float) tinfo.tempo / 60 * 4 / Interval(normalizedSpeed.toBar, mult);
    }
    else {
      _wave.freq = normalizedSpeed * 10;
    }
    if (tinfo.hostIsPlaying) {
      _wave.popFront(tinfo.timeInSamples);
    }
  }

  void setMidi(MidiMessage midi) pure @system {
    if (midi.isNoteOn) {
      if (_nplay == 0) {
        _wave.phase = 0;
      }
      ++_nplay;
    }
    else if (midi.isNoteOff) {
      --_nplay;
    }
  }

  float front() const { return _wave.front; }
  void popFront() pure { _wave.popFront(); }
  alias empty = _wave.empty;

 private:
  int _nplay;
  WaveformRange _wave;
}
