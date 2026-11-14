// Watches Engine.state() once a second (from UiClock) and raises banner notifications:
//   TIME ADDED  - the bank went up (an activity or bonus was credited)
//   TIME'S UP   - the bank crossed from zero or positive into overdraft (silent: the Engine buzzes for overdraft)
//   TIME OUT    - scrolling during night hours (bedtime, tax doubles); once per scroll session
import Toybox.Lang;

module Alerts {
    var _prev as Number? = null;
    var _nightWarned as Boolean = false;

    function check(st as Dictionary) as Void {
        var b = st[:balanceSec];
        if (b instanceof Number) {
            var bal = b as Number;
            var prev = _prev;
            // The first reading only sets the baseline, so nothing fires at app start.
            if (prev != null) {
                if (bal > prev) {
                    Notify.show("TIME ADDED", ListUi.signedTime(bal - prev) + " to your bank", true);
                } else if (prev >= 0 && bal < 0) {
                    // No buzz here: the Engine already vibrates on overdraft.
                    Notify.show("TIME'S UP", "bank empty, now in overdraft", false);
                }
            }
            _prev = bal;
        }

        var scrolling = st[:scrolling] == true;
        if (!scrolling) {
            _nightWarned = false;
        } else if (st[:night] == true && !_nightWarned) {
            _nightWarned = true;
            var m = st[:multiplier];
            Notify.show("TIME OUT", "bedtime: scrolling costs " + ((m instanceof Number) ? "x" + m : "more"), true);
        }
    }
}
