// "Earn time": every Catalog activity grouped by kind, with its exchange rate.
// Daily activities already claimed today are greyed out and cannot be started.
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class ActivityPickerView extends WatchUi.View {
    private const GROUPS = [:exercise, :chore, :calm, :outdoor] as Array<Symbol>;
    private const GROUP_NAMES = ["EXERCISE", "CHORES", "CALM", "OUTDOORS"] as Array<String>;

    private var _rows as Array<Dictionary> = [] as Array<Dictionary>;
    private var _focus as Number = 0;
    // Brief message shown in place of the title (e.g. after a refused start); cleared on the next move.
    private var _notice as String? = null;

    public function initialize() {
        View.initialize();
    }

    // Rebuilt on every show so "claimed today" is current after a session.
    public function onShow() as Void {
        var keep = (_rows.size() > 0) ? rowId(_focus) : null;
        _rows = buildRows();
        _focus = ListUi.nextSelectable(_rows, 0, 1);
        if (keep != null) {
            for (var i = 0; i < _rows.size(); i++) {
                if (_rows[i][:id] == keep) {
                    _focus = i;
                }
            }
        }
        if (_focus < 0) {
            _focus = 0;
        }
    }

    private function rowId(i as Number) as Symbol? {
        return (i >= 0 && i < _rows.size()) ? _rows[i][:id] as Symbol? : null;
    }

    private function buildRows() as Array<Dictionary> {
        var all = Catalog.all();
        var rows = [] as Array<Dictionary>;
        // Walk goes first, above every header.
        for (var i = 0; i < all.size(); i++) {
            if (all[i][:id] == :walk) {
                rows.add(entryRow(all[i]));
            }
        }
        for (var g = 0; g < GROUPS.size(); g++) {
            var first = true;
            for (var i = 0; i < all.size(); i++) {
                var e = all[i];
                if (e[:group] != GROUPS[g] || e[:id] == :walk) {
                    continue;
                }
                if (first) {
                    rows.add({:title => GROUP_NAMES[g], :header => true});
                    first = false;
                }
                rows.add(entryRow(e));
            }
        }
        return rows;
    }

    private function entryRow(e as Dictionary) as Dictionary {
        var id = e[:id] as Symbol;
        var claimed = e[:daily] == true && Ledger.claimedToday(id);
        var label = e[:label];
        return {
            :id => id,
            :title => (label != null) ? label as String : "",
            :sub => claimed ? "claimed today" : rateText(e),
            :sub2 => (e[:verify] == :partly) ? "partly verified" : null,
            :disabled => claimed
        };
    }

    // "+3s per rep", "+1.5 min per min", "+2 min per floor"; walking is paid per km.
    public static function rateText(e as Dictionary) as String {
        var rate = e[:rate];
        var r = (rate != null) ? (rate as Numeric).toFloat() : 0.0;
        var unit = e[:unit];
        if (e[:detector] == :walk) {
            return "+" + num(Ledger.WALK_SEC_PER_KM / 60.0) + " min per km";
        }
        if (unit == :rep) {
            return "+" + num(r) + "s per rep";
        }
        if (unit == :floor) {
            return "+" + num(r / 60.0) + " min per floor";
        }
        return "+" + num(r) + " min per min";
    }

    // 3.0 -> "3", 1.5 -> "1.5", 0.75 -> "0.75".
    public static function num(f as Float) as String {
        if (f == f.toNumber().toFloat()) {
            return f.toNumber().toString();
        }
        if (f * 10 == (f * 10).toNumber().toFloat()) {
            return f.format("%.1f");
        }
        return f.format("%.2f");
    }

    public function move(dir as Number) as Void {
        _focus = ListUi.move(_rows, _focus, dir);
        _notice = null;
        WatchUi.requestUpdate();
    }

    public function select() as Void {
        if (_focus < 0 || _focus >= _rows.size()) {
            return;
        }
        var row = _rows[_focus];
        if (row[:disabled] == true) {
            _notice = "already claimed today";
            WatchUi.requestUpdate();
            return;
        }
        var id = row[:id] as Symbol?;
        if (id == null) {
            return;
        }
        var v = new ActivitySessionView(id);
        WatchUi.pushView(v, new ActivitySessionDelegate(v), WatchUi.SLIDE_LEFT);
    }

    public function onUpdate(dc as Dc) as Void {
        var n = _notice;
        ListUi.draw(dc, (n != null) ? n : "EARN TIME", _rows, _focus);
    }
}

class ActivityPickerDelegate extends WatchUi.BehaviorDelegate {
    private var _view as ActivityPickerView;

    public function initialize(view as ActivityPickerView) {
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
