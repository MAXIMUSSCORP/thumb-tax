// Badges: the list (with streak header), a detail page per badge, and the "NEW BADGE" screen.
// The Engine already buzzes when a badge is earned, so these screens never vibrate.
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

module BadgeUi {
    // "3/7 days", or "earned x2" for repeatable badges already earned.
    function progressText(id as Symbol) as String {
        var n = Badges.earnedCount(id);
        var p = Badges.progress(id);
        var cur = p[:current];
        var tgt = p[:target];
        var unit = p[:unit];
        var prog = (cur instanceof Number && tgt instanceof Number)
            ? cur + "/" + tgt + ((unit instanceof String && !(unit as String).equals("times")) ? " " + unit : "")
            : "";
        if (n > 0) {
            return "earned" + (n > 1 ? " x" + n : "") + (prog.equals("") ? "" : " · " + prog);
        }
        return prog;
    }

    // Short date for a Unix time, e.g. "Nov 14".
    function dateText(t as Number?) as String {
        if (t == null) {
            return "";
        }
        var info = Gregorian.info(new Time.Moment(t), Time.FORMAT_MEDIUM);
        return info.month + " " + info.day;
    }

    // Progress bar: outlined track, white fill.
    function bar(dc as Dc, x as Number, y as Number, w as Number, cur as Number, tgt as Number) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(x, y, w, 10, 5);
        if (tgt > 0 && cur > 0) {
            var fw = (w - 4) * (cur > tgt ? tgt : cur) / tgt;
            if (fw > 0) {
                dc.fillRoundedRectangle(x + 2, y + 2, fw, 6, 3);
            }
        }
    }
}

class BadgeListView extends WatchUi.View {
    private var _rows as Array<Dictionary> = [] as Array<Dictionary>;
    private var _focus as Number = 0;

    public function initialize() {
        View.initialize();
    }

    public function onShow() as Void {
        var all = Badges.all();
        var rows = [] as Array<Dictionary>;
        var earned = [] as Array<Dictionary>;
        var locked = [] as Array<Dictionary>;
        for (var i = 0; i < all.size(); i++) {
            var id = all[i][:id] as Symbol;
            var name = all[i][:name];
            var row = {:id => id, :title => (name instanceof String) ? name : "", :sub => BadgeUi.progressText(id),
                :mark => Badges.earnedCount(id) > 0};
            if (Badges.earnedCount(id) > 0) {
                earned.add(row);
            } else {
                locked.add(row);
            }
        }
        if (earned.size() > 0) {
            rows.add({:title => "EARNED", :header => true});
            rows.addAll(earned);
        }
        rows.add({:title => "TO EARN", :header => true});
        rows.addAll(locked);
        _rows = rows;
        if (_focus >= _rows.size() || !ListUi.isSelectable(_rows[_focus])) {
            _focus = ListUi.nextSelectable(_rows, 0, 1);
        }
        UiClock.listen(self, method(:onTimer));
    }

    public function onHide() as Void {
        UiClock.release(self);
    }

    public function onTimer() as Void {
        WatchUi.requestUpdate();
    }

    public function move(dir as Number) as Void {
        _focus = ListUi.move(_rows, _focus, dir);
        WatchUi.requestUpdate();
    }

    public function select() as Void {
        if (_focus < 0 || _focus >= _rows.size()) {
            return;
        }
        var id = _rows[_focus][:id] as Symbol?;
        if (id != null) {
            var v = new BadgeDetailView(id);
            WatchUi.pushView(v, new WatchUi.BehaviorDelegate(), WatchUi.SLIDE_LEFT);
        }
    }

    public function onUpdate(dc as Dc) as Void {
        ListUi.draw(dc, "STREAK " + Badges.streak() + " · BEST " + Badges.bestStreak(), _rows, _focus);
    }
}

class BadgeListDelegate extends WatchUi.BehaviorDelegate {
    private var _view as BadgeListView;

    public function initialize(view as BadgeListView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    public function onNextPage() as Boolean {
        _view.move(1);
        return true;
    }

    public function onPreviousPage() as Boolean {
        _view.move(-1);
        return true;
    }

    public function onSelect() as Boolean {
        _view.select();
        return true;
    }
}

class BadgeDetailView extends WatchUi.View {
    private var _id as Symbol;

    public function initialize(id as Symbol) {
        View.initialize();
        _id = id;
    }

    public function onShow() as Void {
        UiClock.listen(self, method(:onTimer));
    }

    public function onHide() as Void {
        UiClock.release(self);
    }

    public function onTimer() as Void {
        WatchUi.requestUpdate();
    }

    public function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var c = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var def = Badges.get(_id);
        var n = Badges.earnedCount(_id);
        var name = (def != null && def[:name] instanceof String) ? def[:name] as String : "";
        var desc = (def != null && def[:desc] instanceof String) ? def[:desc] as String : "";

        Icons.medal(dc, cx, (h * 0.21).toNumber(), 22, n > 0);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var title = ListUi.wrap(dc, name, Graphics.FONT_TINY, (w * 0.8).toNumber());
        for (var i = 0; i < title.size(); i++) {
            dc.drawText(cx, (h * 0.40).toNumber() + i * 22 - (title.size() - 1) * 11, Graphics.FONT_TINY, title[i], c);
        }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        var lines = ListUi.wrap(dc, desc, Graphics.FONT_XTINY, (w * 0.78).toNumber());
        for (var i = 0; i < lines.size(); i++) {
            dc.drawText(cx, (h * 0.53).toNumber() + i * 17, Graphics.FONT_XTINY, lines[i], c);
        }

        var p = Badges.progress(_id);
        var cur = p[:current];
        var tgt = p[:target];
        if (cur instanceof Number && tgt instanceof Number) {
            var bw = (w * 0.56).toNumber();
            BadgeUi.bar(dc, cx - bw / 2, (h * 0.66).toNumber(), bw, cur, tgt);
            var unit = p[:unit];
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.745).toNumber(), Graphics.FONT_XTINY,
                cur + " / " + tgt + ((unit instanceof String) ? " " + unit : ""), c);
        }

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        var foot = "not earned yet";
        if (n > 0) {
            var when = BadgeUi.dateText(Badges.lastEarnedAt(_id));
            foot = "earned" + (n > 1 ? " x" + n : "") + (when.equals("") ? "" : " · " + when);
        }
        dc.drawText(cx, (h * 0.835).toNumber(), Graphics.FONT_XTINY, foot, c);
        Notify.draw(dc);
    }
}

// Celebrates each unseen badge in turn; START or BACK shows the next, then marks them seen and closes.
class BadgeUnlockedView extends WatchUi.View {
    private var _ids as Array<Symbol>;
    private var _i as Number = 0;
    private var _tick as Number = 0;

    public function initialize(ids as Array<Symbol>) {
        View.initialize();
        _ids = ids;
    }

    public function onShow() as Void {
        UiClock.listen(self, method(:onTimer));
    }

    public function onHide() as Void {
        UiClock.release(self);
    }

    public function onTimer() as Void {
        _tick += 1;
        WatchUi.requestUpdate();
    }

    // Returns true while there is another badge to show.
    public function next() as Boolean {
        _i += 1;
        _tick = 0;
        WatchUi.requestUpdate();
        return _i < _ids.size();
    }

    public function close() as Void {
        Badges.markSeen();
        BadgeWatch.closed();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    public function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var c = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        if (_i >= _ids.size()) {
            return;
        }
        var id = _ids[_i];
        var def = Badges.get(id);
        var name = (def != null && def[:name] instanceof String) ? def[:name] as String : "";
        var desc = (def != null && def[:desc] instanceof String) ? def[:desc] as String : "";

        // Rays that blink every other second around the medal.
        var my = (h * 0.33).toNumber();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        var r0 = (_tick % 2 == 0) ? 36 : 40;
        for (var a = 0; a < 360; a += 45) {
            var rad = Math.toRadians(a);
            var dx = Math.cos(rad);
            var dy = Math.sin(rad);
            dc.drawLine(cx + (dx * r0).toNumber(), my + (dy * r0).toNumber(), cx + (dx * (r0 + 8)).toNumber(), my + (dy * (r0 + 8)).toNumber());
        }
        dc.setPenWidth(1);
        Icons.medal(dc, cx, my, 24, true);

        // Inverted "NEW BADGE" pill.
        var pill = "NEW BADGE";
        var py = (h * 0.12).toNumber();
        var pw = dc.getTextWidthInPixels(pill, Graphics.FONT_XTINY) + 18;
        var ph = dc.getFontHeight(Graphics.FONT_XTINY) + 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cx - pw / 2, py - ph / 2, pw, ph, ph / 2);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, py, Graphics.FONT_XTINY, pill, c);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var title = ListUi.wrap(dc, name, Graphics.FONT_SMALL, (w * 0.8).toNumber());
        for (var i = 0; i < title.size(); i++) {
            dc.drawText(cx, (h * 0.58).toNumber() + i * 24, Graphics.FONT_SMALL, title[i], c);
        }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        var lines = ListUi.wrap(dc, desc, Graphics.FONT_XTINY, (w * 0.76).toNumber());
        var dy0 = (h * 0.58).toNumber() + title.size() * 24 + 2;
        for (var i = 0; i < lines.size(); i++) {
            dc.drawText(cx, dy0 + i * 17, Graphics.FONT_XTINY, lines[i], c);
        }
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        var more = (_ids.size() > 1) ? (_i + 1) + "/" + _ids.size() + " · START" : "START";
        dc.drawText(cx, (h * 0.9).toNumber(), Graphics.FONT_XTINY, more, c);
        Notify.draw(dc);
    }
}

class BadgeUnlockedDelegate extends WatchUi.BehaviorDelegate {
    private var _view as BadgeUnlockedView;

    public function initialize(view as BadgeUnlockedView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    public function onSelect() as Boolean {
        if (!_view.next()) {
            _view.close();
        }
        return true;
    }

    public function onBack() as Boolean {
        _view.close();
        return true;
    }
}

// Pushes the NEW BADGE screen when the Engine reports unseen badges (checked from UiClock).
module BadgeWatch {
    var _shown as Boolean = false;

    function check(st as Dictionary) as Void {
        var n = st[:unseenBadges];
        if (_shown || !(n instanceof Number) || (n as Number) <= 0) {
            return;
        }
        var ids = Badges.unseen();
        if (ids.size() == 0) {
            return;
        }
        _shown = true;
        var v = new BadgeUnlockedView(ids);
        WatchUi.pushView(v, new BadgeUnlockedDelegate(v), WatchUi.SLIDE_UP);
    }

    function closed() as Void {
        _shown = false;
    }
}
