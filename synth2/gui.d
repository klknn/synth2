/**
   Copyright: klknn, 2021.
   License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module synth2.gui;

private {
import dplug.core : mallocNew, destroyFree;
import dplug.graphics.color : RGBA;
import dplug.graphics.font : Font;
import dplug.client : Parameter;
import dplug.pbrwidgets : PBRBackgroundGUI, UILabel, UIOnOffSwitch;
import gfm.math : box2i;
}

// import synth2.label : UILabel;

// for pbrwidgets


enum png = "white600.png"; // "black.png"
// http://www.publicdomainfiles.com/show_file.php?id=13502494517207
static string _fontRaw = import("LeroyLetteringLightBeta01.ttf");
// https://www.google.com/get/noto/#mono-mono
// static string _fontRaw = import("NotoMono-Regular.ttf");

class Synth2GUI : PBRBackgroundGUI!(png, "black600.png", png, png, png, "")
{
public:
  nothrow @nogc:
      
  enum marginW = 10;
  enum marginH = 10;
  enum screenWidth = 600;
  enum screenHeight = 300;

  this(Parameter[] parameters...)
  {
    _font = mallocNew!Font(cast(ubyte[])(_fontRaw));
    super(screenWidth, screenHeight);

    int y;

    // header
    y = marginH;
    auto synth2 = addLabel("Synth2");
    synth2.position(box2i.rectangle(marginW, y, 100, 50));
    auto date = addLabel(__DATE__);
    date.position(box2i.rectangle(screenWidth - 150, y, 100, 50));
    date.textSize(10);

    // osc section
    // y += 50;
    auto osc = addLabel("[Oscillators]");
    osc.position(box2i.rectangle(marginW + 20, 30, 100, 50));
    
    // addOnOffSwitch("saw", box2i.rectangle(marginW, screenWidth - 100, 10, 10));
  }

  ~this()
  {
    _font.destroyFree();
  }

  void addOnOffSwitch(string text, box2i rect) {
    UIOnOffSwitch sw;
    // addChild(sw = mallocNew!UIOnOffSwitch(context(), BoolParameter param)
  }

  UILabel addLabel(string text) {
    UILabel label;
    addChild(label = mallocNew!UILabel(context(), _font, text));
    label.textColor(RGBA(0, 0, 0, 0));
    // label.textColor(RGBA(255, 255, 255, 0));
    return label;
  }

private:
  Font _font;
}

