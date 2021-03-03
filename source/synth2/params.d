/**
   Synth2 parameters.

   Copyright: klknn 2021.
   License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module synth2.params;

import std.traits : EnumMembers;

import dplug.core.nogc : destroyFree, mallocNew;
import dplug.core.vec : makeVec, Vec;
import dplug.client.params : BoolParameter, EnumParameter, FloatParameter,
  GainParameter, IntegerParameter, LinearFloatParameter, LogFloatParameter,
  Parameter, PowFloatParameter;
import mir.math.constant : PI;

import synth2.effect : EffectKind, effectNames;
import synth2.waveform : Waveform, waveformNames;
import synth2.filter : filterNames, FilterKind;

/// Parameter ids.
enum Params : int {
  /// Oscillator section
  osc1Waveform,
  osc1Det,
  osc1FM,

  osc2Waveform,
  osc2Ring,
  osc2Sync,
  osc2Track,
  osc2Pitch,
  osc2Fine,

  oscMix,
  oscKeyShift,
  oscTune,
  oscPhase,

  oscPulseWidth,
  oscSubWaveform,
  oscSubVol,
  oscSubOct,

  /// Amp section
  ampAttack,
  ampDecay,
  ampSustain,
  ampRelease,
  ampGain,
  ampVel,

  /// Filter section
  filterKind,
  filterCutoff,
  filterQ,
  filterTrack,
  filterAttack,
  filterDecay,
  filterSustain,
  filterRelease,
  filterEnvAmount,
  filterUseVelocity,
  saturation,

  /// Mod envelope
  menvDest,
  menvAttack,
  menvDecay,
  menvAmount,

  /// LFO1
  // lfo1Wave,
  // lfo1Dest,
  // lfo1Speed,
  // lfo1Amount,
  // lfo1Key,

  /// LFO2

  /// Effect
  effectKind,
  effectCtrl1,
  effectCtrl2,
  effectMix,
}

static immutable paramNames = [__traits(allMembers, Params)];

/// Modulation envelope destination.
enum MEnvDest {
  osc2,
  fm,
  pw,
}

static immutable menvDestNames = [__traits(allMembers, MEnvDest)];

/// LFO modulation destination.
enum LfoDest {
  osc2,
  osc12,
  amo,
  pw,
  fm,
  pan,
}

/// Setup default parameter.
struct ParamBuilder {

  static osc1Waveform() {
    return mallocNew!EnumParameter(
        Params.osc1Waveform, "Osc1/Wave", waveformNames, Waveform.sine);
  }

  static osc1Det() {
    return mallocNew!LinearFloatParameter(
        Params.osc1Det, "Osc1/Detune", "", 0, 1, 0);
  }

  static osc1FM() {
    return mallocNew!LinearFloatParameter(
        Params.osc1FM, "Osc1/FM", "", 0, 10, 0);
  }

  static osc2Waveform() {
    return mallocNew!EnumParameter(
        Params.osc2Waveform, "Osc2/Wave", waveformNames, Waveform.triangle);
  }

  static osc2Track() {
    return mallocNew!BoolParameter(Params.osc2Track, "Osc2/Track", true);
  }

  // TODO: check synth1 default (440hz?)
  static osc2Pitch() {
    return mallocNew!IntegerParameter(
        Params.osc2Pitch, "Osc2/Pitch", "", -12, 12, 0);
  }

  static osc2Fine() {
    return mallocNew!LinearFloatParameter(
        Params.osc2Fine, "Osc2/Fine", "", -1.0, 1.0, 0.0);
  }

  static osc2Ring() {
    return mallocNew!BoolParameter(Params.osc2Ring, "Osc2/Ring", false);
  }

  static osc2Sync() {
    return mallocNew!BoolParameter(Params.osc2Sync, "Osc2/Sync", false);
  }

  static oscMix() {
    return mallocNew!LinearFloatParameter(
        Params.oscMix, "Osc/Mix", "", 0f, 1f, 0f);
  }

  static oscKeyShift() {
    return mallocNew!IntegerParameter(
        Params.oscKeyShift, "Osc/KeyShift", "semitone", -12, 12, 0);
  }

  static oscTune() {
    return mallocNew!LinearFloatParameter(
        Params.oscTune, "Osc/Tune", "cent", -1.0, 1.0, 0);
  }

  enum float ignoreOscPhase = -PI;

  static oscPhase() {
    return mallocNew!LinearFloatParameter(
        Params.oscPhase, "Osc/Phase", "", -PI, PI, ignoreOscPhase);
  }

  static oscPulseWidth() {
    return mallocNew!LinearFloatParameter(
        Params.oscPulseWidth, "Osc/PW", "", 0f, 1f, 0.5f);
  }

  static oscSubWaveform() {
    return mallocNew!EnumParameter(
        Params.oscSubWaveform, "OscSub/Wave", waveformNames, Waveform.sine);
  }

  // TODO: check synth1 max vol.
  static oscSubVol() {
    return mallocNew!GainParameter(
        Params.oscSubVol, "OscSub/Gain", 3, -float.infinity);
  }

  static oscSubOct() {
    return mallocNew!BoolParameter(Params.oscSubOct, "OscSub/-1Oct", false);
  }

  // Epsilon value to avoid NaN in log.
  enum logBias = 1e-3;

  static ampAttack() {
    return mallocNew!LogFloatParameter(
        Params.ampAttack, "Amp/Attack", "sec", logBias, 100.0, logBias);
  }

  static ampDecay() {
    return mallocNew!LogFloatParameter(
        Params.ampDecay, "Amp/Decay", "sec", logBias, 100.0, logBias);
  }

  static ampSustain() {
    return mallocNew!GainParameter(
        Params.ampSustain, "Amp/Sustain", 0.0, 0.0);
  }

  static ampRelease() {
    return mallocNew!LogFloatParameter(
        Params.ampRelease, "Amp/Release", "sec", logBias, 100, logBias);
  }

  static ampGain() {
    return mallocNew!GainParameter(Params.ampGain, "Amp/Gain", 3.0, 0.0);
  }

  static ampVel() {
    return mallocNew!LinearFloatParameter(
        Params.ampVel, "Amp/Velocity", "", 0, 1.0, 1.0);
  }

  static filterKind() {
    return mallocNew!EnumParameter(
        Params.filterKind, "Filter/Kind", filterNames, FilterKind.LP12);
  }

  static filterCutoff() {
    return mallocNew!LogFloatParameter(
        Params.filterCutoff, "Filter/Cutoff", "", logBias, 1, 1);
  }

  static filterQ() {
    return mallocNew!LinearFloatParameter(
        Params.filterQ, "Filter/Q", "", 0, 1, 0);
  }

  static filterTrack() {
    return mallocNew!LinearFloatParameter(
        Params.filterTrack, "Filter/Track", "", 0, 1, 0);
  }

  static filterEnvAmount() {
    return mallocNew!LinearFloatParameter(
        Params.filterEnvAmount, "Filter/Amount", "", 0, 1, 0);
  }

  static filterAttack() {
    return mallocNew!LogFloatParameter(
        Params.filterAttack, "Filter/Attack", "sec", logBias, 100.0, logBias);
  }

  static filterDecay() {
    return mallocNew!LogFloatParameter(
        Params.filterDecay, "Filter/Decay", "sec", logBias, 100.0, logBias);
  }

  static filterSustain() {
    return mallocNew!GainParameter(
        Params.filterSustain, "Filter/Sustain", 0.0, 0.0);
  }

  static filterRelease() {
    return mallocNew!LogFloatParameter(
        Params.filterRelease, "Filter/Release", "sec", logBias, 100, logBias);
  }

  static filterUseVelocity() {
    return mallocNew!BoolParameter(
        Params.filterUseVelocity, "Filter/Velocity", false);
  }

  static saturation() {
    return mallocNew!LinearFloatParameter(
        Params.saturation, "Saturation", "", 0, 100, 0);
  }

  static menvDest() {
    return mallocNew!EnumParameter(
        Params.menvDest, "MEnv/Destination", menvDestNames, MEnvDest.osc2);
  }

  static menvAttack() {
    return mallocNew!LogFloatParameter(
        Params.menvAttack, "MEnv/Attack", "sec", logBias, 100.0, logBias);
  }

  static menvDecay() {
    return mallocNew!LogFloatParameter(
        Params.menvDecay, "MEnv/Decay", "sec", logBias, 100.0, logBias);
  }

  static menvAmount() {
    return mallocNew!LinearFloatParameter(
        Params.menvAmount, "MEnv/Amount", "", -100, 100, 0);
  }

  static effectKind() {
    return mallocNew!EnumParameter(
        Params.effectKind, "Effect/Kind", effectNames, EffectKind.ad1);
  }

  static effectCtrl1() {
    return mallocNew!LinearFloatParameter(
        Params.effectCtrl1, "Effect/Ctrl1", "", 0, 1, 0.5);
  }

  static effectCtrl2() {
    return mallocNew!LinearFloatParameter(
        Params.effectCtrl2, "Effect/Ctrl2", "", 0, 1, 0.5);
  }

  static effectMix() {
    return mallocNew!LinearFloatParameter(
        Params.effectMix, "Effect/Mix", "", 0, 1, 0);
  }

  @nogc nothrow:
  static Parameter[] buildParameters() {
    auto params = makeVec!Parameter(EnumMembers!Params.length);
    static foreach (i, pname; paramNames) {
      params[i] = __traits(getMember, ParamBuilder, pname)();
      assert(i == params[i].index, pname ~ " has wrong index.");
    }
    return params.releaseData();
  }
}

/// Gets statically-known typed param from base class array.
auto typedParam(Params pid)(Parameter[] params) {
  alias T = typeof(__traits(getMember, ParamBuilder, paramNames[pid])());
  auto ret = cast(T) params[pid];
  assert(ret !is null);
  return ret;
}

///
@nogc nothrow
unittest {
  Parameter[1] ps;
  ps[0] = ParamBuilder.osc1Waveform();
  auto actual = typedParam!(Params.osc1Waveform)(ps[]);
  static assert(is(typeof(actual) == EnumParameter));
}
