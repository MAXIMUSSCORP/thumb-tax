// Demo control for the simulator: where "is the user scrolling?" comes from.
// Phone server = follow the phone feed (ScrollSource.setManual(null)); the other two force it on or off.
// The title shows whether the phone feed is connected, from Engine.state()[:online].
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class ScrollFeedView extends WatchUi.View {
    // Index 0 = follow server (null), 1 = force scrolling (true), 2 = force idle (false).
    private var _focus as Number = 0;

    public function initialize() {
        View.initialize();
    }

    public function onShow() as Void {
        _focus = currentIndex();
        UiClock.listen(self, method(:onTimer));
    }

    public function onHide() as Void {
        UiClock.release(self);
    }

    public function onTimer() as Void {
        WatchUi.requestUpdate();
    }

    private function currentIndex() as Number {
        var m = Engine.state()[:manual];
        if (m == true) {
            return 1;
        }
        if (m == false) {
            return 2;
        }
        return 0;
    }

    public function move(dir as Number) as Void {
        var n = _focus + dir;
        if (n >= 0 && n <= 2) {
            _focus = n;
            WatchUi.requestUpdate();
        }
    }

    public function select() as Void {
        if (_focus == 1) {
            ScrollSource.setManual(true);
        } else if (_focus == 2) {
            ScrollSource.setManual(false);
        } else {
            ScrollSource.setManual(null);
        }
        WatchUi.requestUpdate();
    }

    public function onUpdate(dc as Dc) as Void {
        var st = Engine.state();
        var online = st[:online] == true;
        var scrolling = st[:scrolling] == true;
        var cur = currentIndex();
        var rows = [
            {:title => "Phone server", :sub => online ? "feed connected" : "feed offline", :mark => cur == 0},
            {:title => "Force scrolling", :sub => "demo: charge tax now", :mark => cur == 1},
            {:title => "Force idle", :sub => "demo: no scrolling", :mark => cur == 2}
        ] as Array<Dictionary>;
        // Title doubles as the live status: feed connection and whether scrolling is being charged.
        var status = (online ? "ONLINE" : "OFFLINE") + " · " + (scrolling ? "scrolling" : "idle");
        ListUi.draw(dc, status, rows, _focus);

        // Connection dot before the title: filled = connected, hollow = offline.
        var cx = dc.getWidth() / 2;
        var y = (dc.getHeight() * 0.11).toNumber();
        var tw = dc.getTextWidthInPixels(status, Graphics.FONT_XTINY);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        if (online) {
            dc.fillCircle(cx - tw / 2 - 9, y, 4);
        } else {
            dc.drawCircle(cx - tw / 2 - 9, y, 4);
        }
    }
}

class ScrollFeedDelegate extends WatchUi.BehaviorDelegate {
    private var _view as ScrollFeedView;

    public function initialize(view as ScrollFeedView) {
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
