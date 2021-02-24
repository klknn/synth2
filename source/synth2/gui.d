/**
   Copyright: klknn, 2021.
   License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module synth2.gui;

version (unittest) {} else:

import dplug.core : mallocNew, destroyFree;
import dplug.graphics.color : RGBA;
import dplug.graphics.font : Font;
// import dplug.client : Parameter;
import dplug.client.params;
import dplug.pbrwidgets; // : PBRBackgroundGUI, UILabel, UIOnOffSwitch, UIKnob;
import gfm.math : box2i;

import synth2.filter : filterNames;
import synth2.params : typedParam, Params;

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
  enum screenWidth = 460;
  enum screenHeight = 300;

  enum fontLarge = 16;
  enum fontMedium = 10;
  enum fontSmall = 8;

  enum knobRad = 30;
  enum slideWidth = 50;
  enum slideHeight = 100;

  this(Parameter[] parameters)
  {
    _font = mallocNew!Font(cast(ubyte[])(_fontRaw));
    super(screenWidth, screenHeight);
    int x, y;

    // header
    y = marginH;
    auto synth2 = addLabel("Synth2");
    synth2.textSize(fontLarge);
    synth2.position(box2i.rectangle(0, y, 80, fontLarge));
    auto url = addLabel("https://github.com/klknn/synth2");
    url.targetURL = "https://github.com/klknn/synth2";
    url.clickable = true;
    url.textSize(fontSmall);
    url.position(box2i.rectangle(screenWidth * 2 / 3,
                                 screenHeight - fontMedium, 150, fontMedium));
    auto date = addLabel("v0.00 " ~ __DATE__);
    date.position(box2i.rectangle(screenWidth - 100, y, 100, fontMedium));
    date.textSize(fontMedium);



    static immutable waveNames = ["sin", "saw", "pls", "tri", "rnd"];

    // osc section
    // y += 50;
    // auto oscLab = addLabel("[Oscillators]");
    // oscLab.textSize(fontMedium);
    // oscLab.position(box2i.rectangle(marginW, synth2.position.max.y + marginH,
    //                                 80, fontMedium));
    // osc1
    auto osc1lab = this.addLabel("Osc1");
    osc1lab.textSize(fontMedium);
    osc1lab.position(box2i.rectangle(
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
        box2i.rectangle(
            osc1wave.position.max.x + osc1wave.position.width + marginW,
            osc1wave.position.min.y, knobRad, knobRad),
        "det");
    auto osc1fm = this.addKnob(
          cast(FloatParameter) parameters[Params.osc1FM],
          box2i.rectangle(
              osc1det.position.min.x,
              osc1det.position.max.y + fontSmall + marginH / 2,
              knobRad, knobRad),
          "fm");


    // oscSub
    auto oscSublab = this.addLabel("OscSub");
    oscSublab.textSize(fontMedium);
    oscSublab.position(box2i.rectangle(
        osc1det.position.max.x,
        osc1lab.position.min.y,
        50, fontMedium));
    auto oscSubwave = this.addSlider(
        parameters[Params.oscSubWaveform],
        box2i.rectangle(
            oscSublab.position.min.x + marginW, osc1wave.position.min.y,
            slideWidth, slideHeight),
        "wave",
        waveNames,
    );
    auto oscSubVol = this.addKnob(
        cast(FloatParameter) parameters[Params.oscSubVol],
        box2i.rectangle(
            oscSubwave.position.max.x + oscSubwave.position.width + marginW,
            oscSubwave.position.min.y,
            knobRad, knobRad),
        "vol  ");
    auto oscSubOct = this.addSwitch(
        typedParam!(Params.oscSubOct)(parameters),
        box2i.rectangle(oscSubVol.position.min.x,
                        osc1fm.position.min.y,
                        knobRad, knobRad),
        "-1oct"
    );


    // osc2
    auto osc2lab = this.addLabel("Osc2");
    osc2lab.textSize(fontMedium);
    osc2lab.position(box2i.rectangle(
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
        box2i.rectangle(osc1det.position.min.x,
                        osc2wave.position.min.y,
                        knobRad, knobRad),
        "ring"
    );
    auto osc2sync = this.addSwitch(
        typedParam!(Params.osc2Sync)(parameters),
        box2i.rectangle(osc2ring.position.min.x,
                        osc2ring.position.max.y + marginH * 3,
                        knobRad, knobRad),
        "sync"
    );
    static const pitchLabels = ["-12", "-6", "0", "6", "12"];
    auto osc2pitch = this.addSlider(
        parameters[Params.osc2Pitch],
        box2i.rectangle(
            oscSubwave.position.min.x, osc2ring.position.min.y,
            slideWidth, slideHeight),
        "pitch", pitchLabels);
    auto osc2tune = this.addKnob(
        cast(FloatParameter) parameters[Params.osc2Fine],
        box2i.rectangle(
            oscSubVol.position.min.x,
            osc2ring.position.min.y,
            knobRad, knobRad),
        "tune");
    auto osc2track = this.addSwitch(
        typedParam!(Params.osc2Track)(parameters),
        box2i.rectangle(osc2tune.position.min.x,
                        osc2sync.position.min.y,
                        knobRad, knobRad),
        "track"
    );

    // osc misc
    auto oscMaster = this.addLabel("Master");
    oscMaster.textSize(fontMedium);
    oscMaster.position(box2i.rectangle(
        oscSubVol.position.max.x + marginW,
        oscSublab.position.min.y,
        40, fontMedium));
    auto oscKeyShift = this.addSlider(
        parameters[Params.oscKeyShift],
        box2i.rectangle(oscMaster.position.min.x + marginW,
                        osc1wave.position.min.y,
                        slideWidth, slideHeight),
        "shift", pitchLabels);
    auto oscMasterMix = this.addKnob(
        typedParam!(Params.oscMix)(parameters),
        box2i.rectangle(
            oscKeyShift.position.max.x + oscKeyShift.position.width + marginW,
            osc1det.position.min.y,
            knobRad, knobRad),
        "mix",
    );
    auto oscMasterPhase = this.addKnob(
        typedParam!(Params.oscPhase)(parameters),
        box2i.rectangle(oscMasterMix.position.min.x,
                        osc1fm.position.min.y,
                        knobRad, knobRad),
        "phase",
    );
    auto oscMasterPW = this.addKnob(
        typedParam!(Params.oscPulseWidth)(parameters),
        box2i.rectangle(oscMasterMix.position.max.x + marginW,
                        oscMasterMix.position.min.y,
                        knobRad, knobRad),
        "p/w",
    );
    auto oscMasterTune = this.addKnob(
        typedParam!(Params.oscTune)(parameters),
        box2i.rectangle(oscMasterPW.position.min.x,
                        oscMasterPhase.position.min.y,
                        knobRad, knobRad),
        "tune",
    );

    // Amplifier
    auto ampLab = this.addLabel("Amplifier");
    ampLab.textSize(fontMedium);
    ampLab.position(box2i.rectangle(
        oscMasterPW.position.max.x + marginW,
        osc1lab.position.min.y,
        50, fontMedium));
    auto ampA = this.addKnob(
        typedParam!(Params.ampAttack)(parameters),
        box2i.rectangle(ampLab.position.min.x + marginW,
                        oscMasterPW.position.min.y,
                        knobRad, knobRad),
        "A",
    );
    auto ampD = this.addKnob(
        typedParam!(Params.ampDecay)(parameters),
        box2i.rectangle(ampA.position.max.x + marginW,
                        oscMasterPW.position.min.y,
                        knobRad, knobRad),
        "D",
    );
    auto ampS = this.addKnob(
        typedParam!(Params.ampSustain)(parameters),
        box2i.rectangle(ampD.position.max.x + marginW,
                        oscMasterPW.position.min.y,
                        knobRad, knobRad),
        "S",
    );
    auto ampR = this.addKnob(
        typedParam!(Params.ampRelease)(parameters),
        box2i.rectangle(ampS.position.max.x + marginW,
                        oscMasterPW.position.min.y,
                        knobRad, knobRad),
        "R",
    );
    auto ampGain = this.addKnob(
        typedParam!(Params.ampGain)(parameters),
        box2i.rectangle(ampA.position.max.x + marginW,
                        oscMasterTune.position.min.y,
                        knobRad, knobRad),
        "gain",
    );
    auto ampVel = this.addKnob(
        typedParam!(Params.ampVel)(parameters),
        box2i.rectangle(ampD.position.max.x + marginW,
                        oscMasterTune.position.min.y,
                        knobRad, knobRad),
        "vel",
    );

    // Filter
    auto filterLab = this.addLabel("Filter");
    filterLab.textSize(fontMedium);
    filterLab.position(box2i.rectangle(
        oscMaster.position.min.x,
        osc2lab.position.min.y,
        30, fontMedium));
    auto filterKind = this.addSlider(
        parameters[Params.filterKind],
        box2i.rectangle(oscKeyShift.position.min.x, osc2pitch.position.min.y,
                        slideWidth, slideHeight),
        "type", filterNames);
    auto filterCutoff = this.addKnob(
        typedParam!(Params.filterCutoff)(parameters),
        box2i.rectangle(oscMasterMix.position.min.x,
                        filterKind.position.min.y,
                        knobRad, knobRad),
        "cutoff");
    auto filterQ = this.addKnob(
        typedParam!(Params.filterQ)(parameters),
        box2i.rectangle(oscMasterMix.position.min.x,
                        osc2track.position.min.y,
                        knobRad, knobRad),
        "Q");
  }

  UIKnob addKnob(FloatParameter p, box2i pos, string label) {
    UIKnob knob = mallocNew!UIKnob(this.context, p);
    this.addChild(knob);
    knob.position(pos);
    knob.style = KnobStyle.cylinder;
    // knob.knobDiffuse = RGBA(255, 255, 255, 255);
    knob.knobDiffuse = defaultDiffuse;
    knob.numLEDs = 0;
    knob.knobRadius = 0.5;
    knob.trailRadiusMin = 0.4;
    knob.trailRadiusMax = 1;
    knob.LEDDiffuseLit = RGBA(0, 0, 40, 100);
    knob.LEDDiffuseUnlit = RGBA(0, 0, 40, 0);
    knob.LEDRadiusMin = 0.2f;
    knob.LEDRadiusMax = 0.2f;

    knob.litTrailDiffuse = litTrailDiffuse;
    knob.unlitTrailDiffuse = unlitTrailDiffuse;
    auto lab = this.addLabel(label);
    lab.textSize(fontSmall);
    lab.position(box2i.rectangle(knob.position.min.x - marginW, knob.position.max.y,
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
    lab.position(box2i.rectangle(pos.min.x - pos.width / 2, pos.max.y,
                                 pos.width * 2, fontSmall));
    return ui;
  }

  UISlider addSlider(Parameter p, box2i pos, string label, const string[] vlabels) {
    UISlider ui = mallocNew!UISlider(this.context, p);
    pos.width(pos.width / 2);
    ui.position = pos;
    ui.trailWidth = 0.5;
    ui.handleWidthRatio = 0.5;
    ui.handleHeightRatio = 0.12;
    ui.handleStyle = HandleStyle.shapeBlock;
    ui.handleDiffuse = RGBA(255, 255, 255, 0);
    ui.litTrailDiffuse = litTrailDiffuse;
    ui.unlitTrailDiffuse = unlitTrailDiffuse;
    ui.handleMaterial = RGBA(0, 0, 0, 0);  // smooth, metal, shiny, phisycal
    this.addChild(ui);

    if (vlabels.length > 0) {
      uint labelHeight = pos.height / cast(uint) vlabels.length;
      foreach (i, lab; vlabels) {
        UILabel l = addLabel(lab);
        l.position(box2i.rectangle(
            pos.min.x + pos.width,
            cast(uint) (pos.min.y + (vlabels.length - i - 1) * labelHeight),
            pos.width, labelHeight));
        l.textSize(fontSmall);
      }
    }

    auto lab = this.addLabel(label);
    lab.textSize(fontSmall);
    lab.position(box2i.rectangle(pos.min.x, pos.max.y, 20, 20));
    return ui;
  }

  enum defaultDiffuse = RGBA(50, 50, 100, 0);
  // enum litTrailDiffuse = RGBA(151, 119, 255, 100);
  enum litTrailDiffuse = RGBA(150, 0, 192, 0);
  enum unlitTrailDiffuse = RGBA(81, 54, 108, 0);
  enum fontColor = RGBA(0, 0, 0, 0);

  ~this()
  {
    _font.destroyFree();
  }

  UILabel addLabel(string text) {
    UILabel label;
    addChild(label = mallocNew!UILabel(context(), _font, text));
    label.textColor(fontColor);
    return label;
  }

private:
  Font _font;
}
