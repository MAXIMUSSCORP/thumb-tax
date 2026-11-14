// Live scroll-tax meter: the sleep being charged right now, ticking once a second from Engine.state().
// Overdraft inverts the whole screen (white page, black ink) so it reads without colour; the Engine vibrates.
// When opened automatically, it closes itself a few seconds after scrolling stops.
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class ScrollMeterView extends WatchUi.View {
    private const CLOSE_AFTER_SEC = 4;

    private var _auto as Boolean;
    private var _st as Dictionary = {} as Dictionary;
    // The Engine zeroes the session when scrolling stops; keep the last values for the closing frame.
    private var _lastSec as Number = 0;
    private var _lastCharged as Number = 0;
    private var _idleSec as Number = 0;

    public function initialize(auto as Boolean) {
        View.initialize();
        _auto = auto;
    }

    public function onShow() as Void {
        refresh();
        UiClock.listen(self, method(:onTimer));
    }

    public function onHide() as Void {
        UiClock.release(self);
    }

    public function onTimer() as Void {
        refresh();
        if (_auto && !isTrue(:scrolling)) {
            _idleSec += 1;
            if (_idleSec >= CLOSE_AFTER_SEC) {
                close(false);
                return;
            }
        } else {
            _idleSec = 0;
        }
        WatchUi.requestUpdate();
    }

    public function close(byUser as Boolean) as Void {
        onHide();
        ScrollWatch.meterClosed(byUser);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    private function refresh() as Void {
        _st = Engine.state();
        var s = numOf(:sessionSec);
        if (s > 0) {
            _lastSec = s;
            _lastCharged = numOf(:sessionChargedSec);
        }
    }

    private function isTrue(k as Symbol) as Boolean {
        return _st[k] == true;
    }

    private function numOf(k as Symbol) as Number {
        var v = _st[k];
        return (v instanceof Number) ? v as Number : ((v instanceof Float) ? (v as Float).toNumber() : 0);
    }

    public function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var c = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        var overdrawn = isTrue(:overdrawn);
        var scrolling = isTrue(:scrolling);
        var ink = overdrawn ? Graphics.COLOR_BLACK : Graphics.COLOR_WHITE;
        var paper = overdrawn ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
        var soft = overdrawn ? Graphics.COLOR_DK_GRAY : Graphics.COLOR_LT_GRAY;

        dc.setColor(ink, paper);
        dc.clear();

        var charged = scrolling ? numOf(:sessionChargedSec) : _lastCharged;
        var secs = scrolling ? numOf(:sessionSec) : _lastSec;

        // Seconds ring: a full lap per minute of sleep charged, so the meter visibly ticks.
        dc.setPenWidth(5);
        dc.setColor(overdrawn ? Graphics.COLOR_LT_GRAY : Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, h / 2, cx - 5);
        var frac = (charged % 60) / 60.0;
        if (frac > 0) {
            dc.setColor(ink, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, h / 2, cx - 5, Graphics.ARC_CLOCKWISE, 90, 90 - (360 * frac).toNumber());
        }
        dc.setPenWidth(1);

        // Title with phone icon.
        var title = overdrawn ? "OVERDRAFT" : "SCROLL TAX";
        var ty = (h * 0.13).toNumber();
        var tw = dc.getTextWidthInPixels(title, Graphics.FONT_XTINY);
        Icons.phone(dc, cx - tw / 2 - 12, ty, 8, ink);
        dc.setColor(ink, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + 6, ty, Graphics.FONT_XTINY, title, c);

        // Multiplier pill, inverted against the page.
        var pill = multiplierText();
        var py = (h * 0.23).toNumber();
        var pw = dc.getTextWidthInPixels(pill, Graphics.FONT_XTINY) + 16;
        var ph = dc.getFontHeight(Graphics.FONT_XTINY) + 2;
        dc.setColor(ink, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cx - pw / 2, py - ph / 2, pw, ph, ph / 2);
        dc.setColor(paper, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, py, Graphics.FONT_XTINY, pill, c);

        // Charged so far.
        dc.setColor(ink, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.42).toNumber(), Graphics.FONT_NUMBER_MEDIUM, "-" + clock(charged), c);
        dc.setColor(soft, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.545).toNumber(), Graphics.FONT_XTINY, "min of sleep", c);

        // Session line: time scrolling and average heart rate.
        var line = (scrolling ? "scrolling " : "scrolled ") + clock(secs);
        var avg = _st[:sessionAvgHr];
        if (avg instanceof Number) {
            line += " · " + avg + " bpm";
        }
        dc.setColor(ink, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.635).toNumber(), Graphics.FONT_XTINY, line, c);

        // Bank balance.
        var bal = numOf(:balanceSec);
        var balText = (_st[:balanceSec] == null) ? "--" : ListUi.signedTime(bal);
        dc.drawText(cx, (h * 0.715).toNumber(), Graphics.FONT_XTINY, "bank " + balText, c);

        // State line: in overdraft, the payoff suggestion ("12 push-ups or a 3 min walk clears it").
        var note = "";
        var sug = _st[:suggestion];
        if (overdrawn && sug instanceof String && !(sug as String).equals("")) {
            note = sug as String;
        } else if (!scrolling) {
            note = "session closed";
        } else if (overdrawn) {
            note = "put the phone down";
        }
        if (!note.equals("")) {
            dc.setColor(soft, Graphics.COLOR_TRANSPARENT);
            var lines = ListUi.wrap(dc, note, Graphics.FONT_XTINY, (w * 0.7).toNumber());
            var y0 = (h * ((lines.size() > 1) ? 0.77 : 0.8)).toNumber();
            for (var i = 0; i < lines.size(); i++) {
                dc.drawText(cx, y0 + i * 16, Graphics.FONT_XTINY, lines[i], c);
            }
        }

        // The footer only fits when the state line is a single line.
        if (note.equals("") || dc.getTextWidthInPixels(note, Graphics.FONT_XTINY) <= (w * 0.7).toNumber()) {
            dc.setColor(soft, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.9).toNumber(), Graphics.FONT_XTINY, "BACK hide", c);
        }
        Notify.draw(dc);
    }

    // "x1 day", "x2 night", "x3 in bed".
    private function multiplierText() as String {
        var m = _st[:multiplier];
        var x = (m instanceof Number) ? "x" + m : "x?";
        if (isTrue(:inBed)) {
            return x + " in bed";
        }
        return x + (isTrue(:night) ? " night" : " day");
    }

    private function clock(sec as Number) as String {
        return (sec / 60) + ":" + (sec % 60).format("%02d");
    }
}

class ScrollMeterDelegate extends WatchUi.BehaviorDelegate {
    private var _view as ScrollMeterView;

    public function initialize(view as ScrollMeterView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    public function onBack() as Boolean {
        _view.close(true);
        return true;
    }
}
