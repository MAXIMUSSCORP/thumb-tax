// One activity session: starts it, redraws from Activities.progress() every second, and shows the credit.
// START = stop and bank the time, BACK = cancel. For rep and tilt detectors, DOWN/UP or a screen tap
// counts one rep by hand (the simulator has no motion data).
// "Counting" vs "paused" is shown by inversion: a white card while counting, an outlined card when paused.
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class ActivitySessionView extends WatchUi.View {
    private var _id as Symbol;
    private var _detector as Symbol? = null;
    private var _label as String = "";
    // :refused, :running or :done.
    private var _state as Symbol = :refused;
    private var _p as Dictionary = {} as Dictionary;
    private var _credited as Number = 0;
    private var _listening as Boolean = false;
    private var _started as Boolean = false;
    private var _tick as Number = 0;

    public function initialize(id as Symbol) {
        View.initialize();
        _id = id;
        var e = Catalog.get(id);
        if (e != null) {
            _detector = e[:detector] as Symbol?;
            var l = e[:label];
            _label = (l != null) ? l as String : "";
        }
    }

    public function onShow() as Void {
        if (!_started) {
            _started = true;
            _state = Activities.start(_id) ? :running : :refused;
            refresh();
        }
        if (_state == :running) {
            startTimer();
        }
    }

    public function onHide() as Void {
        stopTimer();
    }

    // Ticks come from UiClock: Activities holds the third (last) timer while a session runs.
    private function startTimer() as Void {
        UiClock.listen(self, method(:onTimer));
        _listening = true;
    }

    private function stopTimer() as Void {
        if (_listening) {
            UiClock.release(self);
            _listening = false;
        }
    }

    public function onTimer() as Void {
        _tick += 1;
        refresh();
        WatchUi.requestUpdate();
    }

    private function refresh() as Void {
        if (_state == :running) {
            _p = Activities.progress();
        }
    }

    public function countsTaps() as Boolean {
        return _state == :running && (_detector == :reps || _detector == :tilt);
    }

    public function tap() as Void {
        if (countsTaps()) {
            Activities.tapRep();
            refresh();
            WatchUi.requestUpdate();
        }
    }

    // START: bank the session. On the result or refusal screen it closes the view.
    public function finish() as Boolean {
        if (_state != :running) {
            return false;
        }
        _credited = Activities.stop();
        _state = :done;
        stopTimer();
        WatchUi.requestUpdate();
        return true;
    }

    // BACK: cancel a running session (nothing is credited).
    public function cancel() as Void {
        if (_state == :running) {
            Activities.cancel();
            _state = :refused;
        }
        stopTimer();
    }

    public function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        if (_state == :done) {
            drawResult(dc);
        } else if (_state == :running) {
            drawRunning(dc);
        } else {
            drawRefused(dc);
        }
    }

    private function drawRunning(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var c = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var p = _p;

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.12).toNumber(), ListUi.fit(dc, _label, Graphics.FONT_TINY, (w * 0.6).toNumber()), _label, c);

        // Counting / paused pill, by inversion.
        var valid = p[:valid] == true;
        var pill = valid ? "COUNTING" : "PAUSED";
        var py = (h * 0.23).toNumber();
        var pw = dc.getTextWidthInPixels(pill, Graphics.FONT_XTINY) + 22;
        var ph = dc.getFontHeight(Graphics.FONT_XTINY) + 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        if (valid) {
            dc.fillRoundedRectangle(cx - pw / 2, py - ph / 2, pw, ph, ph / 2);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            // Small pulsing dot: on every other second.
            if (_tick % 2 == 0) {
                dc.fillCircle(cx - pw / 2 + 9, py, 3);
            }
        } else {
            dc.setPenWidth(2);
            dc.drawRoundedRectangle(cx - pw / 2, py - ph / 2, pw, ph, ph / 2);
            dc.setPenWidth(1);
        }
        dc.drawText(cx + 4, py, Graphics.FONT_XTINY, pill, c);

        // Big count.
        var count = num(p[:count]);
        var unit = p[:unit];
        var big = count.toString();
        var caption = "";
        if (_detector == :walk) {
            big = (count / 1000.0).format("%.2f");
            var climb = num(p[:climbM]);
            caption = "km" + ((climb > 0) ? "  · climb " + climb + " m" : "");
        } else if (unit == :rep) {
            caption = (count == 1) ? "rep" : "reps";
        } else if (unit == :floor) {
            caption = (count == 1) ? "floor" : "floors";
        } else {
            big = clock(count);
            caption = "counted";
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.41).toNumber(), Graphics.FONT_NUMBER_MEDIUM, big, c);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.535).toNumber(), Graphics.FONT_XTINY, caption, c);

        // Elapsed.
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.62).toNumber(), Graphics.FONT_XTINY, "elapsed " + clock(num(p[:elapsedSec])), c);

        // Hint, up to two lines.
        var hint = p[:hint];
        if (hint != null && !(hint as String).equals("")) {
            var lines = ListUi.wrap(dc, hint as String, Graphics.FONT_XTINY, (w * 0.72).toNumber());
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            for (var i = 0; i < lines.size(); i++) {
                dc.drawText(cx, (h * 0.69).toNumber() + i * 17, Graphics.FONT_XTINY, lines[i], c);
            }
        }

        // ESTIMATED tag: outlined, so it reads without colour.
        if (p[:estimated] == true) {
            var ty = (h * 0.82).toNumber();
            var tag = "ESTIMATED";
            var tw = dc.getTextWidthInPixels(tag, Graphics.FONT_XTINY) + 12;
            var th = dc.getFontHeight(Graphics.FONT_XTINY);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawRectangle(cx - tw / 2, ty - th / 2, tw, th);
            dc.drawText(cx, ty, Graphics.FONT_XTINY, tag, c);
        }

        // Footer must stay short: the round screen is narrow this low.
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.905).toNumber(), Graphics.FONT_XTINY, countsTaps() ? "DOWN +1 · START" : "START done", c);
    }

    private function drawResult(dc as Dc) as Void {
        var h = dc.getHeight();
        var cx = dc.getWidth() / 2;
        var c = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var earned = _credited > 0;

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.12).toNumber(), Graphics.FONT_XTINY, earned ? "TAX RETURN" : "NOT CREDITED", c);
        Avatar.draw(dc, cx, (h * 0.38).toNumber(), (h * 0.3).toNumber(),
            earned ? Avatar.MOOD_REWARD : Avatar.MOOD_CLEAR, 0);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.64).toNumber(), Graphics.FONT_MEDIUM, "+" + creditText(_credited), c);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.73).toNumber(), Graphics.FONT_XTINY,
            earned ? "added to your bank" : "too short or not verified", c);
        dc.drawText(cx, (h * 0.79).toNumber(), Graphics.FONT_XTINY, _label, c);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.9).toNumber(), Graphics.FONT_XTINY, "START / BACK close", c);
    }

    private function drawRefused(dc as Dc) as Void {
        var h = dc.getHeight();
        var w = dc.getWidth();
        var cx = w / 2;
        var c = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.2).toNumber(), Graphics.FONT_XTINY, _label, c);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.42).toNumber(), Graphics.FONT_MEDIUM, "Can't start", c);
        var why = ["Another activity is running,", "it's claimed today, or it's", "outside its time window."] as Array<String>;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < why.size(); i++) {
            dc.drawText(cx, (h * 0.56).toNumber() + i * 18, Graphics.FONT_XTINY, why[i], c);
        }
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.88).toNumber(), Graphics.FONT_XTINY, "BACK", c);
    }

    // Seconds credited -> "12 min", or "40s" under a minute.
    public static function creditText(sec as Number) as String {
        if (sec > 0 && sec < 60) {
            return sec + "s";
        }
        return ((sec + 30) / 60) + " min";
    }

    private function num(v as Object?) as Number {
        return (v instanceof Number) ? v as Number : ((v instanceof Float) ? (v as Float).toNumber() : 0);
    }

    private function clock(sec as Number) as String {
        return (sec / 60) + ":" + (sec % 60).format("%02d");
    }
}

class ActivitySessionDelegate extends WatchUi.BehaviorDelegate {
    private var _view as ActivitySessionView;

    public function initialize(view as ActivitySessionView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    public function onSelect() as Boolean {
        if (!_view.finish()) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
        return true;
    }

    public function onBack() as Boolean {
        _view.cancel();
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    public function onNextPage() as Boolean {
        _view.tap();
        return true;
    }

    public function onPreviousPage() as Boolean {
        _view.tap();
        return true;
    }

    // A screen tap counts a rep instead of being turned into START, so a stray touch can't end the session.
    public function onTap(evt as WatchUi.ClickEvent) as Boolean {
        _view.tap();
        return true;
    }
}
