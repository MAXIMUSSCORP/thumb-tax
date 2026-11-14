// Pushes the live scroll meter over whatever screen is open as soon as the Engine reports scrolling.
// Checked once a second from UiClock (no timer of its own; the device timer budget is used by the backend).
// If the user hides the meter mid-session it stays hidden until that scrolling session ends.
import Toybox.Lang;
import Toybox.WatchUi;

module ScrollWatch {
    var _shown as Boolean = false;
    var _dismissed as Boolean = false;

    function check(st as Dictionary) as Void {
        var scrolling = st[:scrolling] == true;
        if (!scrolling) {
            _dismissed = false;
            return;
        }
        if (!_shown && !_dismissed) {
            open(true);
        }
    }

    // Opens the meter; auto = true when triggered by scrolling (it then closes itself when scrolling stops).
    function open(auto as Boolean) as Void {
        if (_shown) {
            return;
        }
        _shown = true;
        var v = new ScrollMeterView(auto);
        WatchUi.pushView(v, new ScrollMeterDelegate(v), WatchUi.SLIDE_UP);
    }

    function meterClosed(byUser as Boolean) as Void {
        _shown = false;
        if (byUser && Engine.state()[:scrolling] == true) {
            _dismissed = true;
        }
    }
}
