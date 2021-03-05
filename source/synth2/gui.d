/**
   Synth2 graphical user interface.

   Copyright: klknn, 2021.
   License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module synth2.gui;

version (unittest) {} else:

import dplug.core : mallocNew, destroyFree;
import dplug.graphics.color : RGBA;
import dplug.graphics.font : Font;
import dplug.client.params : BoolParameter, FloatParameter, Parameter;
import dplug.pbrwidgets : PBRBackgroundGUI, UILabel, UIOnOffSwitch, UIKnob, UISlider, KnobStyle, HandleStyle;
import gfm.math : box2i, rectangle;

import synth2.effect : effectNames;
import synth2.filter : filterNames;
import synth2.params : typedParam, Params, menvDestNames;

enum png1 = "gray600.png"; // "black.png"
enum png2 = "black600.png";
enum png3 = "white600.png";


// https://all-free-download.com/font/download/display_free_tfb_10784.html
// static string _fontRaw = import("TFB.ttf");
// http://www.publicdomainfiles.com/show_file.php?id=13502494517207
// static string _fontRaw = import("LeroyLetteringLightBeta01.ttf");
// https://www.google.com/get/noto/#mono-mono
// static string _fontRaw = import("NotoMono-Regular.ttf");
// https://all-free-download.com/font/download/forced_square_14817.html
static string _fontRaw = import("FORCED SQUARE.ttf");

class Synth2GUI : PBRBackgroundGUI!(png1, png2, png3, png3, png3, "")
{
public:
  nothrow @nogc:

  enum marginW = 5;
  enum marginH = 5;
  enum screenWidth = 420;
  enum screenHeight = 260;

  enum fontLarge = 16;
  enum fontMedium = 10;
  enum fontSmall = 8;

  enum knobRad = 20;
  enum slideWidth = 40;
  enum slideHeight = 80;

  this(Parameter[] parameters)
  {
    _font = mallocNew!Font(cast(ubyte[])(_fontRaw));
    super(screenWidth, screenHeight);
    int x, y;

    // header
    y = marginH;
    auto synth2 = addLabel("Synth2");
    synth2.textSize(fontLarge);
    synth2.position(rectangle(0, y, 80, fontLarge));

    _tempo = addLabel("BPM000.0");
    _tempo.textSize(fontMedium);
    _tempo.position(rectangle(synth2.position.max.x + marginW, synth2.position.min.y,
                              80, fontMedium));

    auto date = addLabel("v0.00 " ~ __DATE__);
    date.position(rectangle(screenWidth - 100, y, 100, fontMedium));
    date.textSize(fontMedium);

    static immutable waveNames = ["sin", "saw", "pls", "tri", "rnd"];

    // osc section
    // y += 50;
    // auto oscLab = addLabel("[Oscillators]");
    // oscLab.textSize(fontMedium);
    // oscLab.position(rectangle(marginW, synth2.position.max.y + marginH,
    //                                 80, fontMedium));
    // osc1
    auto osc1lab = this.addLabel("Osc1");
    osc1lab.textSize(fontMedium);
    osc1lab.position(rectangle(
        marginW, // oscLab.position.min.x + marginW,
        synth2.position.max.y + marginH, // oscLab.position.max.y + marginH,
        25, fontMedium));
    auto osc1wave = this.addSlider(
        parameters[Params.osc1Waveform],
        rectangle(osc1lab.position.min.x, osc1lab.position.max.y + marginH,
                  slideWidth, slideHeight),
        "wave",
        waveNames,
    );
    auto osc1det = this.addKnob(
        cast(FloatParameter) parameters[Params.osc1Det],
        rectangle(
            osc1wave.position.max.x + osc1wave.position.width + marginW,
            osc1wave.position.min.y, knobRad, knobRad),
        "det");
    auto osc1fm = this.addKnob(
          cast(FloatParameter) parameters[Params.osc1FM],
          rectangle(
              osc1det.position.min.x,
              osc1det.position.max.y + fontMedium + marginH,
              knobRad, knobRad),
          "fm");


    // oscSub
    auto oscSublab = this.addLabel("OscSub");
    oscSublab.textSize(fontMedium);
    oscSublab.position(rectangle(
        osc1det.position.max.x,
        osc1lab.position.min.y,
        50, fontMedium));
    auto oscSubwave = this.addSlider(
        parameters[Params.oscSubWaveform],
        rectangle(
            oscSublab.position.min.x + marginW, osc1wave.position.min.y,
            slideWidth, slideHeight),
        "wave",
        waveNames,
    );
    auto oscSubVol = this.addKnob(
        cast(FloatParameter) parameters[Params.oscSubVol],
        rectangle(
            oscSubwave.position.max.x + oscSubwave.position.width + marginW,
            oscSubwave.position.min.y,
            knobRad, knobRad),
        "vol  ");
    auto oscSubOct = this.addSwitch(
        typedParam!(Params.oscSubOct)(parameters),
        rectangle(oscSubVol.position.min.x,
                        osc1fm.position.min.y,
                        knobRad, knobRad),
        "-1oct"
    );


    // osc2
    auto osc2lab = this.addLabel("Osc2");
    osc2lab.textSize(fontMedium);
    osc2lab.position(rectangle(
        osc1lab.position.min.x,
        osc1wave.position.max.y + fontMedium + marginH * 2,
        25, fontMedium));
    auto osc2wave = this.addSlider(
        parameters[Params.osc2Waveform],
        rectangle(osc1wave.position.min.x,
                  osc2lab.position.max.y + marginW,
                  slideWidth, slideHeight),
        "wave",
        waveNames,
    );
    auto osc2ring = this.addSwitch(
        typedParam!(Params.osc2Ring)(parameters),
        rectangle(osc1det.position.min.x,
                        osc2wave.position.min.y,
                        knobRad, knobRad),
        "ring"
    );
    auto osc2sync = this.addSwitch(
        typedParam!(Params.osc2Sync)(parameters),
        rectangle(osc2ring.position.min.x,
                        osc2ring.position.max.y + fontMedium + marginH,
                        knobRad, knobRad),
        "sync"
    );
    static const pitchLabels = ["-12", "-6", "0", "6", "12"];
    auto osc2pitch = this.addSlider(
        parameters[Params.osc2Pitch],
        rectangle(
            oscSubwave.position.min.x, osc2ring.position.min.y,
            slideWidth, slideHeight),
        "pitch", pitchLabels);
    auto osc2tune = this.addKnob(
        cast(FloatParameter) parameters[Params.osc2Fine],
        rectangle(
            oscSubVol.position.min.x,
            osc2ring.position.min.y,
            knobRad, knobRad),
        "tune");
    auto osc2track = this.addSwitch(
        typedParam!(Params.osc2Track)(parameters),
        rectangle(osc2tune.position.min.x,
                        osc2sync.position.min.y,
                        knobRad, knobRad),
        "track"
    );

    // osc misc
    auto oscMaster = this.addLabel("Master");
    oscMaster.textSize(fontMedium);
    oscMaster.position(rectangle(
        oscSubVol.position.max.x + marginW,
        oscSublab.position.min.y,
        40, fontMedium));
    auto oscKeyShift = this.addSlider(
        parameters[Params.oscKeyShift],
        rectangle(oscMaster.position.min.x + marginW,
                        osc1wave.position.min.y,
                        slideWidth, slideHeight),
        "shift", pitchLabels);
    auto oscMasterMix = this.addKnob(
        typedParam!(Params.oscMix)(parameters),
        rectangle(
            oscKeyShift.position.max.x + oscKeyShift.position.width + marginW,
            osc1det.position.min.y,
            knobRad, knobRad),
        "mix",
    );
    auto oscMasterPhase = this.addKnob(
        typedParam!(Params.oscPhase)(parameters),
        rectangle(oscMasterMix.position.min.x,
                        osc1fm.position.min.y,
                        knobRad, knobRad),
        "phase",
    );
    auto oscMasterPW = this.addKnob(
        typedParam!(Params.oscPulseWidth)(parameters),
        rectangle(oscMasterMix.position.max.x + marginW,
                        oscMasterMix.position.min.y,
                        knobRad, knobRad),
        "p/w",
    );
    auto oscMasterTune = this.addKnob(
        typedParam!(Params.oscTune)(parameters),
        rectangle(oscMasterPW.position.min.x,
                        oscMasterPhase.position.min.y,
                        knobRad, knobRad),
        "tune",
    );

    // Amplifier
    auto ampGain = this.addKnob(
        typedParam!(Params.ampGain)(parameters),
        rectangle(oscMasterPhase.position.min.x,
                        oscMasterPhase.position.max.y + marginH + fontMedium,
                        knobRad, knobRad),
        "gain",
    );
    auto ampVel = this.addKnob(
        typedParam!(Params.ampVel)(parameters),
        rectangle(oscMasterTune.position.min.x,
                        oscMasterTune.position.max.y + marginH + fontMedium,
                        knobRad, knobRad),
        "vel",
    );

    auto ampLab = this.addLabel("AmpEnv");
    ampLab.textSize(fontMedium);
    ampLab.position(rectangle(
        oscMasterPW.position.max.x + marginW,
        osc1lab.position.min.y,
        50, fontMedium));
    auto ampA = this.addSlider(
        typedParam!(Params.ampAttack)(parameters),
        rectangle(ampLab.position.min.x + marginW,
                        oscMasterPW.position.min.y,
                        slideWidth, slideHeight),
        "A", []
    );
    auto ampD = this.addSlider(
        typedParam!(Params.ampDecay)(parameters),
        rectangle(ampA.position.max.x + marginW,
                        oscMasterPW.position.min.y,
                        slideWidth, slideHeight),
        "D", []
    );
    auto ampS = this.addSlider(
        typedParam!(Params.ampSustain)(parameters),
        rectangle(ampD.position.max.x + marginW,
                        oscMasterPW.position.min.y,
                        slideWidth, slideHeight),
        "S", []
    );
    auto ampR = this.addSlider(
        typedParam!(Params.ampRelease)(parameters),
        rectangle(ampS.position.max.x + marginW,
                        oscMasterPW.position.min.y,
                        slideWidth, slideHeight),
        "R", []
    );

    // Filter
    auto filterLab = this.addLabel("Filter");
    filterLab.textSize(fontMedium);
    filterLab.position(rectangle(
        oscMaster.position.min.x,
        osc2lab.position.min.y,
        30, fontMedium));
    auto filterKind = this.addSlider(
        parameters[Params.filterKind],
        rectangle(oscKeyShift.position.min.x, osc2pitch.position.min.y,
                        slideWidth, slideHeight),
        "type", filterNames);
    auto filterCutoff = this.addKnob(
        typedParam!(Params.filterCutoff)(parameters),
        rectangle(oscMasterMix.position.min.x,
                        filterKind.position.min.y,
                        knobRad, knobRad),
        "frq");
    auto filterQ = this.addKnob(
        typedParam!(Params.filterQ)(parameters),
        rectangle(oscMasterMix.position.min.x,
                        osc2track.position.min.y,
                        knobRad, knobRad),
        "res");
    auto saturation = this.addKnob(
        typedParam!(Params.saturation)(parameters),
        rectangle(oscMasterMix.position.min.x,
                        filterQ.position.max.y + fontMedium + marginH,
                        knobRad, knobRad),
        "sat");
    auto filterEnvAmount = this.addKnob(
        typedParam!(Params.filterEnvAmount)(parameters),
        rectangle(filterCutoff.position.max.x + marginW,
                        filterKind.position.min.y,
                        knobRad, knobRad),
        "amt");
    auto filterTrack = this.addKnob(
        typedParam!(Params.filterTrack)(parameters),
        rectangle(filterEnvAmount.position.min.x,
                        filterQ.position.min.y,
                        knobRad, knobRad),
        "track");
    auto filterVel = this.addSwitch(
        typedParam!(Params.filterUseVelocity)(parameters),
        rectangle(filterTrack.position.min.x,
                        filterTrack.position.max.y + fontMedium + marginH,
                        knobRad, knobRad),
        "vel"
    );

    auto filterEnvLab = this.addLabel("FilterEnv");
    filterEnvLab.textSize(fontMedium);
    filterEnvLab.position(rectangle(
        ampLab.position.min.x,
        filterLab.position.min.y,
        60, fontMedium));
    auto filterA = this.addSlider(
        typedParam!(Params.filterAttack)(parameters),
        rectangle(ampA.position.min.x,
                        filterCutoff.position.min.y,
                        slideWidth, slideHeight),
        "A", []
    );
    auto filterD = this.addSlider(
        typedParam!(Params.filterDecay)(parameters),
        rectangle(filterA.position.max.x + marginW,
                        filterCutoff.position.min.y,
                        slideWidth, slideHeight),
        "D", []
    );
    auto filterS = this.addSlider(
        typedParam!(Params.filterSustain)(parameters),
        rectangle(filterD.position.max.x + marginW,
                        filterCutoff.position.min.y,
                        slideWidth, slideHeight),
        "S", []
    );
    auto filterR = this.addSlider(
        typedParam!(Params.filterRelease)(parameters),
        rectangle(filterS.position.max.x + marginW,
                        filterCutoff.position.min.y,
                        slideWidth, slideHeight),
        "R", []
    );

    // mod env
    auto menvLabel = this.addLabel("ModEnv");
    menvLabel.textSize(fontMedium);
    menvLabel.position(rectangle(
        ampR.position.max.x + marginW,
        osc1lab.position.min.y,
        45, fontMedium));
    auto menvDest = this.addSlider(
        parameters[Params.menvDest],
        rectangle(
            menvLabel.position.min.x,
            menvLabel.position.max.y + marginH,
            slideWidth, slideHeight,
        ), "dst", menvDestNames);
    auto menvAmount = this.addKnob(
        typedParam!(Params.menvAmount)(parameters),
        rectangle(
            menvDest.position.max.x + menvDest.position.width + marginW,
            menvDest.position.min.y,
            knobRad, knobRad),
        "amt");
    auto menvAttack = this.addKnob(
        typedParam!(Params.menvAttack)(parameters),
        rectangle(
            menvAmount.position.min.x,
            menvAmount.position.max.y + fontSmall + marginH,
            knobRad, knobRad),
        "A");
    auto menvDecay = this.addKnob(
        typedParam!(Params.menvDecay)(parameters),
        rectangle(
            menvAmount.position.min.x,
            menvAttack.position.max.y + fontSmall + marginH,
            knobRad, knobRad),
        "D");

    // effect
    auto effectLabel = this.addLabel("Effect");
    effectLabel.textSize = fontMedium;
    effectLabel.position = rectangle(
        menvLabel.position.min.x, filterEnvLab.position.min.y, 50, fontMedium);
    auto effectKind = this.addSlider(
        parameters[Params.effectKind],
        rectangle(effectLabel.position.min.x, filterR.position.min.y, slideWidth, slideHeight),
        "kind", effectNames);
    auto effectCtrl1 = this.addKnob(
        typedParam!(Params.effectCtrl1)(parameters),
        rectangle(effectKind.position.max.x + effectKind.position.width + marginW,
                  effectKind.position.min.y, knobRad, knobRad),
        "ctrl1");
    auto effectCtrl2 = this.addKnob(
        typedParam!(Params.effectCtrl2)(parameters),
        rectangle(effectKind.position.max.x + effectKind.position.width + marginW,
                  effectCtrl1.position.max.y + fontMedium + marginH, knobRad, knobRad),
        "ctrl2");
    auto effectMix = this.addKnob(
        typedParam!(Params.effectMix)(parameters),
        rectangle(effectKind.position.max.x + effectKind.position.width + marginW,
                  effectCtrl2.position.max.y + fontMedium + marginH, knobRad, knobRad),
        "mix");
  }  // this()

  ~this()
  {
    _font.destroyFree();
  }

  char[10] _tempoStr;

  void setTempo(double tempo) {
    import core.stdc.stdio : snprintf;
    snprintf(_tempoStr.ptr, _tempoStr.length, "BPM%3.1lf", tempo);
    _tempo.text(cast(string) _tempoStr[]);
  }

private:

  UIKnob addKnob(FloatParameter p, box2i pos, string label) {
    UIKnob knob = mallocNew!UIKnob(this.context, p);
    this.addChild(knob);
    knob.position(pos);
    // knob.knobDiffuse = RGBA(255, 255, 255, 255);
    knob.knobDiffuse = RGBA(70, 70, 70, 0);
    knob.style = KnobStyle.ball;
    knob.knobMaterial = RGBA(0, 0, 0, 0);  // smooth, metal, shiny, phisycal
    // knob.knobDiffuse = RGBA(255, 255, 255, 255);

    knob.LEDDepth = 0;
    knob.numLEDs = 0;
    knob.knobRadius = 0.5;
    knob.trailRadiusMin = 0.4;
    knob.trailRadiusMax = 1;
    knob.LEDDiffuseLit = RGBA(0, 0, 0, 0);
    knob.LEDDiffuseUnlit = RGBA(0, 0, 0, 0);
    knob.LEDRadiusMin = 0f;
    knob.LEDRadiusMax = 0f;

    knob.litTrailDiffuse = litTrailDiffuse;
    knob.unlitTrailDiffuse = unlitTrailDiffuse;
    auto lab = this.addLabel(label);
    lab.textSize(fontSmall);
    lab.position(rectangle(knob.position.min.x - marginW, knob.position.max.y,
                                 knob.position.width + marginW * 2, fontSmall));
    return knob;
  }

  UIOnOffSwitch addSwitch(BoolParameter p, box2i pos, string label) {
    UIOnOffSwitch ui = mallocNew!UIOnOffSwitch(this.context, p);
    ui.position = pos;
    ui.diffuseOn = litTrailDiffuse;
    ui.diffuseOn.a = 150;
    ui.diffuseOff = unlitTrailDiffuse;
    // ui.depthHigh = 0;
    // ui.material = RGBA(0, 0, 0, 0);
    // ui.orientation = UIOnOffSwitch.Orientation.horizontal;
    this.addChild(ui);
    auto lab = this.addLabel(label);
    lab.textSize(fontSmall);
    lab.position(rectangle(pos.min.x - pos.width / 2, pos.max.y,
                                 pos.width * 2, fontSmall));
    return ui;
  }

  UISlider addSlider(Parameter p, box2i pos, string label, const string[] vlabels) {
    UISlider ui = mallocNew!UISlider(this.context, p);
    pos.width(pos.width / 2);
    ui.position = pos;
    ui.trailWidth = 0.5;
    ui.handleWidthRatio = 0.5;
    ui.handleHeightRatio = 0.15;
    ui.handleStyle = HandleStyle.shapeBlock;
    ui.handleMaterial = RGBA(0, 0, 0, 0);  // smooth, metal, shiny, phisycal
    ui.handleDiffuse = RGBA(255, 255, 255, 0);
    ui.litTrailDiffuse = litTrailDiffuse;
    ui.unlitTrailDiffuse = unlitTrailDiffuse;
    this.addChild(ui);

    if (vlabels.length > 0) {
      uint labelHeight = pos.height / cast(uint) vlabels.length;
      foreach (i, lab; vlabels) {
        UILabel l = addLabel(lab);
        l.position(rectangle(
            pos.min.x + pos.width,
            cast(uint) (pos.min.y + (vlabels.length - i - 1) * labelHeight),
            pos.width, labelHeight));
        l.textSize(fontSmall);
      }
    }

    auto lab = this.addLabel(label);
    lab.textSize(fontSmall);
    lab.position(rectangle(pos.min.x, pos.max.y, 20, 20));
    return ui;
  }

  enum defaultDiffuse = RGBA(50, 50, 100, 0);
  // enum litTrailDiffuse = RGBA(151, 119, 255, 100);
  enum litTrailDiffuse = RGBA(150, 0, 192, 0);
  enum unlitTrailDiffuse = RGBA(81, 54, 108, 0);
  enum fontColor = RGBA(0, 0, 0, 0);

  UILabel addLabel(string text) {
    UILabel label;
    addChild(label = mallocNew!UILabel(context(), _font, text));
    label.textColor(fontColor);
    return label;
  }

  Font _font;
  UILabel _tempo;
}
