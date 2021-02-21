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
  GainParameter, IntegerParameter, LinearFloatParameter, Parameter;

import synth2.oscillator : Waveform, waveformNames;


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
  // oscKeyShift,
  oscPulseWidth,
  // oscPhase,
  // oscTune,
  oscSubWaveform,
  oscSubVol,
  oscSubOct,

  /// Amp section
  ampVel,
}

static immutable paramNames = [__traits(allMembers, Params)];


/// Setup default parameter.
struct ParamBuilder {

  static osc1Waveform() {
    return mallocNew!EnumParameter(
        Params.osc1Waveform, "Osc1/Wave", waveformNames, Waveform.sine);
  }

  static osc1Det() {
    return mallocNew!LinearFloatParameter(
        Params.osc1Det, "Osc1/Det", "", 0, 1, 0);
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
        Params.osc2Pitch, "Osc2/Pitch", "", -69, 68, 0);
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
        Params.oscSubVol, "OscSub/Vol", 0.0f, -float.infinity);
  }

  static oscSubOct() {
    return mallocNew!BoolParameter(Params.oscSubOct, "OscSub/-1Oct", false);
  }

  static ampVel() {
    return mallocNew!LinearFloatParameter(
        Params.ampVel, "Amp/Vel", "", 0, 1.0, 0);
  }
  
  @nogc nothrow:
  static Parameter[] buildParameters() {
    auto params = makeVec!Parameter(EnumMembers!Params.length);
    static foreach (i, pname; paramNames) {
      params[i] = __traits(getMember, ParamBuilder, pname)();
    }
    return params.releaseData();
  }
}
