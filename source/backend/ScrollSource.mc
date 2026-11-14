// Why this exists: tells the backend whether the user is scrolling the phone feed right now,
// by polling the phone-side server (or a manual demo override).
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;

// Real devices require HTTPS and route requests through the paired phone;
// only the simulator can reach http://127.0.0.1 directly.
const STATUS_URL = "http://127.0.0.1:8787/status";
const STATUS_KEY = "scrolling";
const POLL_MS = 2000;
const STALE_MS = 6000;

module ScrollSource {
    var _timer as Timer.Timer? = null;
    var _inFlight as Boolean = false;
    var _remote as Boolean = false;
    var _online as Boolean = false;
    var _manual as Boolean? = null;
    var _lastOkMs as Number = 0;
    var _lastCode as Number = 0;

    function start() as Void {
        if (_timer != null) {
            return;
        }
        var t = new Timer.Timer();
        _timer = t;
        t.start(new Lang.Method(ScrollSource, :poll), POLL_MS, true);
        poll();
    }

    function stop() as Void {
        var t = _timer;
        if (t != null) {
            t.stop();
        }
        _timer = null;
        _inFlight = false;
    }

    function poll() as Void {
        if (_inFlight) {
            return;
        }
        _inFlight = true;
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        try {
            Communications.makeWebRequest(STATUS_URL, null, options, new Lang.Method(ScrollSource, :onResponse));
        } catch (e) {
            _inFlight = false;
            _online = false;
        }
    }

    function onResponse(code as Number, data as Dictionary or String or Null) as Void {
        _inFlight = false;
        _lastCode = code;
        var v = (code == 200 && data instanceof Dictionary) ? data[STATUS_KEY] : null;
        if (v instanceof Boolean) {
            _remote = v;
            _online = true;
            _lastOkMs = System.getTimer();
        }
    }

    function isScrolling() as Boolean {
        var m = _manual;
        if (m != null) {
            return m;
        }
        return _remote && _online && (System.getTimer() - _lastOkMs) <= STALE_MS;
    }

    function isOnline() as Boolean {
        return _online && (System.getTimer() - _lastOkMs) <= STALE_MS;
    }

    function setManual(state as Boolean?) as Void {
        _manual = state;
    }

    function manual() as Boolean? {
        return _manual;
    }

    function lastError() as Number {
        return _lastCode;
    }
}
