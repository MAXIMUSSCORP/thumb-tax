// Main menu, opened from the mascot with START or MENU: earn time, live meter, badges, trends, demo.
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class HubView extends WatchUi.View {
    private var _focus as Number = 0;

    public function initialize() {
        View.initialize();
    }

    // Refresh once a second so the feed status and balance stay current.
    public function onShow() as Void {
        UiClock.listen(self, method(:onTimer));
    }

    public function onHide() as Void {
        UiClock.release(self);
    }

    public function onTimer() as Void {
        WatchUi.requestUpdate();
    }

    private function rows() as Array<Dictionary> {
        var st = Engine.state();
        var bal = st[:balanceSec];
        var balText = "--";
        if (bal instanceof Number) {
            balText = ListUi.signedTime(bal as Number);
        }
        var m = st[:manual];
        var feed = (st[:online] == true) ? "feed online" : "feed offline";
        if (m == true) {
            feed = "forced: scrolling";
        } else if (m == false) {
            feed = "forced: idle";
        }
        var streak = st[:streak];
        var unseen = st[:unseenBadges];
        var badges = "streak " + ((streak instanceof Number) ? streak : "--");
        if (unseen instanceof Number && (unseen as Number) > 0) {
            badges += " · " + unseen + " new";
        }
        return [
            {:title => "Earn time", :sub => Catalog.all().size() + " activities"},
            {:title => "Scroll meter", :sub => "bank " + balText},
            {:title => "Badges", :sub => badges},
            {:title => "Trends", :sub => "charts and sensors"},
            {:title => "Demo", :sub => feed}
        ] as Array<Dictionary>;
    }

    public function move(dir as Number) as Void {
        var n = _focus + dir;
        if (n >= 0 && n < 5) {
            _focus = n;
            WatchUi.requestUpdate();
        }
    }

    public function select() as Void {
        if (_focus == 0) {
            var v = new ActivityPickerView();
            WatchUi.pushView(v, new ActivityPickerDelegate(v), WatchUi.SLIDE_LEFT);
        } else if (_focus == 1) {
            ScrollWatch.open(false);
        } else if (_focus == 2) {
            var b = new BadgeListView();
            WatchUi.pushView(b, new BadgeListDelegate(b), WatchUi.SLIDE_LEFT);
        } else if (_focus == 3) {
            var t = new ThumbTaxView();
            WatchUi.pushView(t, new ThumbTaxDelegate(t), WatchUi.SLIDE_LEFT);
        } else {
            var f = new ScrollFeedView();
            WatchUi.pushView(f, new ScrollFeedDelegate(f), WatchUi.SLIDE_LEFT);
        }
    }

    public function onUpdate(dc as Dc) as Void {
        ListUi.draw(dc, "THUMB TAX", rows(), _focus);
    }
}

class HubDelegate extends WatchUi.BehaviorDelegate {
    private var _view as HubView;

    public function initialize(view as HubView) {
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
