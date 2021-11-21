/**
   Synth2 parameters.

   Copyright: klknn 2021.
   License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module synth2.params;

import std.traits : EnumMembers;

import dplug.core.nogc : destroyFree, mallocNew;
import dplug.core.vec : makeVec, Vec;
import dplug.client.params : BoolParameter, EnumParameter, GainParameter,
  IntegerParameter, LinearFloatParameter, LogFloatParameter, Parameter;
import mir.math.constant : PI;

import synth2.delay : DelayKind, delayNames;
import synth2.effect : EffectKind, effectNames;
import synth2.waveform : Waveform, waveformNames;
import synth2.filter : filterNames, FilterKind;
import synth2.lfo : Multiplier, multiplierNames;

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
  lfo1Wave,
  lfo1Dest,
  lfo1Sync,
  lfo1Speed,
  lfo1Mul,
  lfo1Amount,
  lfo1Trigger,

  /// LFO2
  lfo2Wave,
  lfo2Dest,
  lfo2Sync,
  lfo2Speed,
  lfo2Mul,
  lfo2Amount,
  lfo2Trigger,

  /// Effect
  // TODO: add effectOn param.
  effectKind,
  effectCtrl1,
  effectCtrl2,
  effectMix,

  // Equalizer / Pan
  eqFreq,
  eqLevel,
  eqQ,
  eqTone,
  eqPan,

  // Voice
  voiceKind,
  voicePoly,
  voicePortament,
  voicePortamentAuto,

  // Delay
  // TODO: add delayOn param.
  delayKind,
  delayTime,
  delayMul,
  delaySpread,
  delayFeedback,
  delayTone,
  delayMix,

  // Chorus/flanger
  chorusOn,
  chorusMulti,
  chorusTime,
  chorusDepth,
  chorusRate,
  chorusFeedback,
  chorusLevel,
  chorusWidth,
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
  filter,
  amp,
  pw,
  fm,
  pan,
}

static immutable lfoDestNames = [__traits(allMembers, LfoDest)];

/// Voice kind.
enum VoiceKind {
  poly,
  mono,
  legato,
}

enum maxPoly = 16;
static immutable voiceKindNames = [__traits(allMembers, VoiceKind)];

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

  static lfo1Wave() {
    return mallocNew!EnumParameter(
        Params.lfo1Wave, "LFO1/Wave", waveformNames, Waveform.triangle);
  }

  static lfo1Dest() {
    return mallocNew!EnumParameter(
        Params.lfo1Dest, "LFO1/Dest", lfoDestNames, LfoDest.osc12);
  }

  static lfo1Sync() {
    return mallocNew!BoolParameter(Params.lfo1Sync, "LFO1/Sync", true);
  }

  static lfo1Speed() {
    return mallocNew!LinearFloatParameter(
        Params.lfo1Speed, "LFO1/Speed", "", 0, 1, 0.5);
  }

  static lfo1Mul() {
    return mallocNew!EnumParameter(
        Params.lfo1Mul, "LFO1/Mul", multiplierNames, Multiplier.none);
  }

  static lfo1Amount() {
    return mallocNew!LinearFloatParameter(
        Params.lfo1Amount, "LFO1/Amount", "", 0, 1, 0);
  }

  static lfo1Trigger() {
    return mallocNew!BoolParameter(Params.lfo1Trigger, "LFO1/trigger", false);
  }

  static lfo2Wave() {
    return mallocNew!EnumParameter(
        Params.lfo2Wave, "LFO2/Wave", waveformNames, Waveform.triangle);
  }

  static lfo2Dest() {
    return mallocNew!EnumParameter(
        Params.lfo2Dest, "LFO2/Dest", lfoDestNames, LfoDest.osc12);
  }

  static lfo2Sync() {
    return mallocNew!BoolParameter(Params.lfo2Sync, "LFO2/Sync", true);
  }

  static lfo2Speed() {
    return mallocNew!LinearFloatParameter(
        Params.lfo2Speed, "LFO2/Speed", "", 0, 1, 0.5);
  }

  static lfo2Mul() {
    return mallocNew!EnumParameter(
        Params.lfo2Mul, "LFO2/Mul", multiplierNames, Multiplier.none);
  }

  static lfo2Amount() {
    return mallocNew!LinearFloatParameter(
        Params.lfo2Amount, "LFO2/Amount", "", 0, 1, 0);
  }

  static lfo2Trigger() {
    return mallocNew!BoolParameter(Params.lfo2Trigger, "LFO2/Trigger", false);
  }

  static eqFreq() {
    return mallocNew!LogFloatParameter(Params.eqFreq, "EQ/Freq", "", logBias, 1, 0.5);
  }

  static eqLevel() {
    return mallocNew!LinearFloatParameter(Params.eqLevel, "EQ/Level", "", -1, 1, 0);
  }

  static eqQ() {
    return mallocNew!LinearFloatParameter(Params.eqQ, "EQ/Q", "", 0, 1, 0);
  }

  static eqTone() {
    return mallocNew!LinearFloatParameter(Params.eqTone, "EQ/Tone", "", -1, 1, 0);
  }

  static eqPan() {
    return mallocNew!LinearFloatParameter(Params.eqPan, "EQ/Pan", "", -1, 1, 0);
  }

  static voiceKind() {
    return mallocNew!EnumParameter(
        Params.voiceKind, "Voice/Kind", voiceKindNames, VoiceKind.poly);
  }

  static voicePoly() {
    return mallocNew!IntegerParameter(
        Params.voicePoly, "Voice/Poly", "voices", 0, maxPoly, maxPoly);
  }

  static voicePortament() {
    return mallocNew!LogFloatParameter(
        Params.voicePortament, "Voice/Port", "sec", logBias, 1, logBias);
  }

  static voicePortamentAuto() {
    return mallocNew!BoolParameter(Params.voicePortamentAuto, "Voice/Auto", true);
  }

  static delayKind() {
    return mallocNew!EnumParameter(
        Params.delayKind, "DelayKind", delayNames, DelayKind.st);
  }

  static delayTime() {
    return mallocNew!LinearFloatParameter(
        Params.delayTime, "Delay/Time", "", 0, 1, 1);
  }

  static delayMul() {
    return mallocNew!EnumParameter(
        Params.delayMul, "Delay/Mul", multiplierNames, Multiplier.none);
  }

  static delaySpread() {
    return mallocNew!LinearFloatParameter(
        Params.delaySpread, "Delay/Spread", "sec", 0, 0.1, 0);
  }

  static delayFeedback() {
    return mallocNew!LinearFloatParameter(
        Params.delayFeedback, "Delay/Feedback", "", 0, 1, 0);
  }

  static delayTone() {
    return mallocNew!LinearFloatParameter(
        Params.delayTone, "Delay/Tone", "", -1, 1, 0);
  }

  static delayMix() {
    return mallocNew!LinearFloatParameter(
        Params.delayMix, "Delay/Mix", "", 0, 1, 0);
  }

  static chorusOn() {
    return mallocNew!BoolParameter(Params.chorusOn, "Chrous/On", false);
  }

  static chorusMulti() {
    return mallocNew!IntegerParameter(
        Params.chorusMulti, "Chorus/Multi", "mul", 1, 4, 1);
  }

  static chorusTime() {
    return mallocNew!LinearFloatParameter(
        Params.chorusTime, "Chorus/Time", "ms", 3, 40, 11.1);
  }

  static chorusDepth() {
    return mallocNew!LinearFloatParameter(
        Params.chorusDepth, "Chorus/Depth", "", 0, 0.5, 0.25);
  }

  static chorusRate() {
    return mallocNew!LogFloatParameter(
        Params.chorusRate, "Chorus/Rate", "hz", logBias, 20, 0.86);
  }

  static chorusFeedback() {
    return mallocNew!LinearFloatParameter(
        Params.chorusFeedback, "Chorus/Feedback", "", 0, 1, 0);
  }

  static chorusLevel() {
    return mallocNew!GainParameter(
        Params.chorusLevel, "Chorus/Level", 5, 0.28);
  }

  static chorusWidth() {
    return mallocNew!LinearFloatParameter(
        Params.chorusWidth, "Chorus/Width", "", 0, 1, 0);
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

/// Casts types from untyped parameters using parameter id.
/// Params:
///   pid = Params enum id.
///   params = type-erased parameter array.
/// Returns: statically-known typed param.
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
  assert(is(typeof(typedParam!(Params.osc1Waveform)(ps[])) == EnumParameter));
}
