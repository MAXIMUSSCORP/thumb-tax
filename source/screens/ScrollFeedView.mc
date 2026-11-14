// Demo menu for judging, on the simulator or the watch.
//   Phone server / Force scrolling / Force idle: Sync.setManual(null / true / false), where scrolling comes from.
//   Seed badge week: Badges.seedDemo() (six clean days already banked).
//   Close today: Badges.demoCloseToday(); after seeding this earns Perfect Week live and the NEW BADGE screen opens.
// The title shows whether the phone feed is connected, or the sync error when there is one.
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class ScrollFeedView extends WatchUi.View {
    private const ROWS = 5;

    // 0 = follow server, 1 = force scrolling, 2 = force idle, 3 = seed badges, 4 = close today.
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
        if (n >= 0 && n < ROWS) {
            _focus = n;
            WatchUi.requestUpdate();
        }
    }

    public function select() as Void {
        if (_focus == 1) {
            Sync.setManual(true);
        } else if (_focus == 2) {
            Sync.setManual(false);
        } else if (_focus == 3) {
            Badges.seedDemo();
            Notify.show("BADGE WEEK SEEDED", "6 clean days: close today next", false);
        } else if (_focus == 4) {
            Badges.demoCloseToday();
            Notify.show("DAY CLOSED", "checking badges...", false);
        } else {
            Sync.setManual(null);
        }
        WatchUi.requestUpdate();
    }

    public function onUpdate(dc as Dc) as Void {
        var st = Engine.state();
        var online = st[:online] == true;
        var scrolling = st[:scrolling] == true;
        var err = st[:syncErr];
        var cur = currentIndex();
        var streak = st[:streak];
        var rows = [
            {:title => "Phone server", :sub => online ? "feed connected" : "feed offline", :mark => cur == 0},
            {:title => "Force scrolling", :sub => "demo: charge tax now", :mark => cur == 1},
            {:title => "Force idle", :sub => "demo: no scrolling", :mark => cur == 2},
            {:title => "Seed badge week", :sub => "6 clean days banked"},
            {:title => "Close today", :sub => "streak " + ((streak instanceof Number) ? streak : "--") + " · earns badges"}
        ] as Array<Dictionary>;

        // Title doubles as the live status: the sync error if any, else connection and scrolling state.
        var status = (err instanceof String && !(err as String).equals(""))
            ? err as String
            : (online ? "ONLINE" : "OFFLINE") + " · " + (scrolling ? "scrolling" : "idle");
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
