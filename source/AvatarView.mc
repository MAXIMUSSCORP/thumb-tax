// Preview screen for the mascot: UP/DOWN (or swipe) cycles moods, START opens the sensor test screen.
// The amounts shown are placeholders until the detector and tax ledger exist.
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

class AvatarView extends WatchUi.View {
    private const MOODS = [Avatar.MOOD_REWARD, Avatar.MOOD_CLEAR, Avatar.MOOD_TAXED, Avatar.MOOD_SLEEP_DEBT] as Array<Avatar.Mood>;
    private const TITLES = ["TAX RETURN", "ALL CLEAR", "DAY TAX", "SLEEP TAX"] as Array<String>;
    private const AMOUNTS = ["+15 min", "0 owed", "-12 min", "-45 min"] as Array<String>;
    private const NOTES = ["2k steps banked", "no scrolling today", "scrolled at work", "of sleep withdrawn"] as Array<String>;
    private const COLORS = [0x55FF55, 0xFFFFFF, 0xFF5555, 0x55AAFF] as Array<Number>;

    private var _index as Number = 0;
    private var _tick as Number = 0;
    private var _timer as Timer.Timer or Null = null;

    public function initialize() {
        View.initialize();
    }

    public function onShow() as Void {
        var t = new Timer.Timer();
        t.start(method(:onTick), 150, true);
        _timer = t;
    }

    public function onHide() as Void {
        var t = _timer;
        if (t != null) {
            t.stop();
        }
        _timer = null;
    }

    public function onTick() as Void {
        _tick += 1;
        WatchUi.requestUpdate();
    }

    public function cycle(step as Number) as Void {
        var n = MOODS.size();
        _index = (_index + step + n) % n;
        _tick = 0;
        WatchUi.requestUpdate();
    }

    public function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var cx = dc.getWidth() / 2;
        var h = dc.getHeight();
        var j = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var color = COLORS[_index];

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.12).toNumber(), Graphics.FONT_TINY, TITLES[_index], j);

        Avatar.draw(dc, cx, (h * 0.47).toNumber(), (h * 0.38).toNumber(), MOODS[_index], _tick);

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.77).toNumber(), Graphics.FONT_MEDIUM, AMOUNTS[_index], j);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.87).toNumber(), Graphics.FONT_XTINY, NOTES[_index], j);

        // Page dots.
        var n = MOODS.size();
        var gap = 12;
        var x0 = cx - (n - 1) * gap / 2;
        var y = (h * 0.95).toNumber();
        for (var i = 0; i < n; i++) {
            if (i == _index) {
                dc.setColor(color, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x0 + i * gap, y, 4);
            } else {
                dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x0 + i * gap, y, 3);
            }
        }
    }
}

class AvatarDelegate extends WatchUi.BehaviorDelegate {
    private var _view as AvatarView;

    public function initialize(view as AvatarView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    public function onNextPage() as Boolean {
        _view.cycle(1);
        return true;
    }

    public function onPreviousPage() as Boolean {
        _view.cycle(-1);
        return true;
    }

    public function onSelect() as Boolean {
        var sensors = new $.ThumbTaxView();
        WatchUi.pushView(sensors, new $.ThumbTaxDelegate(sensors), WatchUi.SLIDE_LEFT);
        return true;
    }
}
