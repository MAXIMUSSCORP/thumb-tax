// Home screen for the mascot: the mood and amount follow the live time bank from Engine.state().
// UP/DOWN (or swipe) cycles moods as a demo override that holds for 10 s; START or MENU opens the hub.
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

class AvatarView extends WatchUi.View {
    private const MOODS = [Avatar.MOOD_REWARD, Avatar.MOOD_CLEAR, Avatar.MOOD_TAXED, Avatar.MOOD_SLEEP_DEBT] as Array<Avatar.Mood>;
    private const TITLES = ["TAX RETURN", "ALL CLEAR", "DAY TAX", "SLEEP TAX"] as Array<String>;
    private const NOTES = ["time earned back", "no scrolling owed", "scrolling now", "of sleep withdrawn"] as Array<String>;
    private const HOLD_MS = 10000;
    private const REWARD_SEC = 600;
    private const COLORS = [0x55FF55, 0xFFFFFF, 0xFF5555, 0x55AAFF] as Array<Number>;

    private var _index as Number = 0;
    private var _tick as Number = 0;
    private var _timer as Timer.Timer or Null = null;
    // Live values refreshed once a second; _holdUntil is the end of a demo override (0 = none).
    private var _liveMood as Avatar.Mood = Avatar.MOOD_CLEAR;
    private var _amount as String = "0 min";
    private var _stamp as Number = 0;
    private var _holdUntil as Number = 0;

    public function initialize() {
        View.initialize();
    }

    // Reads Engine.state() and the ledger's last earn; picks the live mood and amount text.
    private function refresh() as Void {
        _stamp = System.getTimer();
        var st = Engine.state();
        var b = st[:balanceSec];
        var o = st[:overdrawn];
        var s = st[:scrolling];
        var n = st[:night];
        var bal = (b != null) ? b as Number : 0;
        var overdrawn = (o != null && o == true) || bal < 0;
        var scrolling = s != null && s == true;
        var night = n != null && n == true;

        var mood = Avatar.MOOD_CLEAR;
        if (overdrawn && night) {
            mood = Avatar.MOOD_SLEEP_DEBT;
        } else if (overdrawn || scrolling) {
            mood = Avatar.MOOD_TAXED;
        } else if (bal > 0 && recentEarn()) {
            mood = Avatar.MOOD_REWARD;
        }
        _liveMood = mood;
        _amount = (bal < 0) ? "-" + Records.fmtMin(bal / 60) + " owed" : "+" + Records.fmtMin(bal / 60);
    }

    // True when the newest ledger entry is a credit from the last 10 minutes.
    private function recentEarn() as Boolean {
        var hist = Ledger.history();
        if (hist.size() == 0) {
            return false;
        }
        var e = hist[hist.size() - 1] as Dictionary;
        var t = e[:t];
        var d = e[:delta];
        return t != null && d != null && (d as Number) > 0 && Time.now().value() - (t as Number) <= REWARD_SEC;
    }

    private function liveIndex() as Number {
        for (var i = 0; i < MOODS.size(); i++) {
            if (MOODS[i] == _liveMood) {
                return i;
            }
        }
        return 0;
    }

    public function onShow() as Void {
        refresh();
        if (_holdUntil == 0) {
            _index = liveIndex();
        }
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
        if (System.getTimer() - _stamp >= 1000) {
            var was = _liveMood;
            refresh();
            if (_holdUntil == 0 && _liveMood != was) {
                _index = liveIndex();
                _tick = 0;
            }
        }
        if (_holdUntil != 0 && System.getTimer() >= _holdUntil) {
            _holdUntil = 0;
            _index = liveIndex();
            _tick = 0;
        }
        WatchUi.requestUpdate();
    }

    public function cycle(step as Number) as Void {
        var n = MOODS.size();
        _index = (_index + step + n) % n;
        _holdUntil = System.getTimer() + HOLD_MS;
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
        dc.drawText(cx, (h * 0.77).toNumber(), Graphics.FONT_MEDIUM, _amount, j);
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
        Notify.draw(dc);
    }
}

class AvatarDelegate extends WatchUi.BehaviorDelegate {
    private const EXIT_WINDOW_MS = 2500;

    private var _view as AvatarView;
    private var _backAt as Number = 0;

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

    // The mascot is the app's root, so BACK here would close the app (leaving the simulator's idle screen).
    // The first press only warns; a second press within 2.5 s exits.
    public function onBack() as Boolean {
        var now = System.getTimer();
        if (_backAt != 0 && now - _backAt <= EXIT_WINDOW_MS) {
            return false;
        }
        _backAt = now;
        Notify.show("Press BACK again", "to exit Thumb Tax", false);
        return true;
    }

    // START or MENU (hold UP) opens the hub: earn time, scroll meter, trends, demo feed.
    public function onSelect() as Boolean {
        return openHub();
    }

    public function onMenu() as Boolean {
        return openHub();
    }

    private function openHub() as Boolean {
        var hub = new $.HubView();
        WatchUi.pushView(hub, new $.HubDelegate(hub), WatchUi.SLIDE_LEFT);
        return true;
    }
}
