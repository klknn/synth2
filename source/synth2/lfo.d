/**
   Synth2 LFO (low freq osc) module.

   Copyright: klknn 2021.
   License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module synth2.lfo;

import std.algorithm.comparison : min;
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

/// String names of Multiplier.
static immutable multiplierNames = [__traits(allMembers, Multiplier)];

/// Multiplier conversions to float.
static immutable float[multiplierNames.length] mulToFloat = [
    Multiplier.dot: 1.5f, Multiplier.none: 1f, Multiplier.tri: 1f / 3 ];

/// Inteval for notes.
struct Interval {
  ///
  Bar bar;
  ///
  Multiplier mul;

  @nogc nothrow pure @safe:

  /// Returns: float interval value in bar.
  float toFloat() const {
    return bar * mulToFloat[mul];
  }

  alias toFloat this;
}

@nogc nothrow pure @safe
unittest {
  import std.math : isClose;

  assert(Interval(Bar.x1_8, Multiplier.none).toFloat == 1f / 8);
  assert(Interval(Bar.x1_8, Multiplier.dot).toFloat == 1f / 8 * 1.5);
  assert(isClose(Interval(Bar.x1_8, Multiplier.tri).toFloat, 1f / 8 / 3));
}

/// Converts a float value into an Interval object.
/// Params:
///   x = float value.
/// Returns: Interval.
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

/// Converts interval object with tempo to seconds.
/// Params:
///   i = interval object.
///   tempo = host tempo.
/// Returns: seconds.
float toSeconds(Interval i, float tempo) @nogc nothrow pure @safe {
  // bars / 4 (beat sec) * 60 (beat min) / bpm
  return i.toFloat / 4 * 60 / tempo;
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
    // TODO: create separated functions for sync and non-sync.
    _wave.waveform = waveform;
    if (sync) {
      _wave.freq = 1f / Interval(normalizedSpeed.toBar, mult).toSeconds(tinfo.tempo);
    }
    else {
      _wave.freq = normalizedSpeed * 10;
    }
    // FIXME: this makes sound glitch.
    // if (tinfo.hostIsPlaying) {
    //   _wave.popFront(tinfo.timeInSamples);
    // }
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

  /// Returns: the current LFO amplitude.
  float front() const { return _wave.front; }

  /// Increments LFO timestamp.
  void popFront() pure { _wave.popFront(); }

  alias empty = _wave.empty;

 private:
  int _nplay;
  WaveformRange _wave;
}
