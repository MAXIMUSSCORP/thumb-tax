// Why this exists: two-way sync with the laptop server. It pulls iPhone guarded-app usage (turned into
// scroll seconds) and pushes the watch's debt/credit so the iPhone can block apps while tax is owed.
import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Timer;

// Real devices require HTTPS and route requests through the paired phone;
// only the simulator can reach http://127.0.0.1 directly.
// The public HTTPS tunnel URL goes here; a Cloudflare quick tunnel URL changes every time the tunnel restarts; for local-only testing use http://127.0.0.1:48217 with the simulator's HTTPS requirement setting unticked.
const SERVER_BASE = "https://descriptions-moms-chan-acne.trycloudflare.com";
const API_KEY = "group16";
const POLL_MS = 4000;
const STALE_MS = 12000;
const HEARTBEAT_MS = 20000;
const MAX_CATCHUP_MIN = 120;
// Estimated pace, not measured: used only to word the "walk clears it" suggestion.
const WALK_M_PER_MIN = 80;
const PUSHUP_MAX = 30;
const STAIRS_MAX = 15;
const IN_FLIGHT_TIMEOUT_MS = 10000;
const SYNC_KEY = "sy";

module Sync {
    var _timer as Timer.Timer? = null;
    var _seenDay as String? = null;
    var _seen as Number = 0;
    var _seenEpoch as String? = null;
    var _pendingSec as Number = 0;
    var _manual as Boolean? = null;
    var _lastOkMs as Number = -1;
    var _online as Boolean = false;
    var _lastCode as Number = 0;
    var _lastErr as Number = 0;
    var _fails as Number = 0;
    var _inFlight as Boolean = false;
    var _inFlightSince as Number = 0;
    var _lastPostMs as Number = 0;
    var _lastPosted as String = "";
    var _lastWasPost as Boolean = false;
    var _sending as String = "";

    function usageDelta(seenDay as String?, seen as Number, seenEpoch as String?, day as String, used as Number, epoch as String?) as Array<Number> {
        if (seenDay == null || (epoch != null && seenEpoch != null && !epoch.equals(seenEpoch))) {
            return [0, used];
        }
        var sameDay = day.equals(seenDay);
        if (!sameDay || used >= seen) {
            var d = sameDay ? used - seen : used;
            return [d < MAX_CATCHUP_MIN ? d : MAX_CATCHUP_MIN, used];
        }
        return [0, seen];
    }

    function statusTextFor(code as Number, everOk as Boolean) as String {
        if (code == -1001) {
            return "SYNC -1001 HTTPS";
        }
        if (code == 401) {
            return "SYNC 401 KEY";
        }
        if (code == 200 || (code == 0 && everOk)) {
            return "";
        }
        return everOk ? "SYNC " + code : "SYNC OFFLINE";
    }

    function fail(code as Number) as Void {
        _fails += 1;
        _lastCode = code;
        _lastErr = code;
    }

    function fails() as Number {
        return _fails;
    }

    function statusText() as String {
        return _fails > 0 ? statusTextFor(_lastErr, _lastOkMs >= 0) : "";
    }

    function effBalance(balanceSec as Number, pendingSec as Number, mult as Number) as Number {
        return balanceSec - pendingSec * mult;
    }

    function ceilDiv(a as Number, b as Float) as Number {
        return Math.ceil(a.toFloat() / b).toNumber();
    }

    function suggestion(debtSec as Number) as String {
        if (debtSec <= 0) {
            return "";
        }
        var w = ceilDiv(debtSec, WALK_M_PER_MIN * Ledger.WALK_SEC_PER_KM / 1000.0);
        var p = ceilDiv(debtSec, (Catalog.get(:pushups) as Dictionary)[:rate] as Float);
        if (p <= PUSHUP_MAX) {
            return p + " push-ups or a " + w + " min walk clears it";
        }
        var f = ceilDiv(debtSec, (Catalog.get(:stairs) as Dictionary)[:rate] as Float);
        if (f <= STAIRS_MAX) {
            return f + " floors of stairs or a " + w + " min walk clears it";
        }
        return "A " + w + " min walk clears it";
    }

    function payload(balanceSec as Number, pendingSec as Number, mult as Number) as Dictionary {
        var eff = effBalance(balanceSec, pendingSec, mult);
        var debt = eff < 0 ? -eff : 0;
        return {
            "taxMinutes" => (debt + 59) / 60,
            "creditMinutes" => (eff > 0 ? eff : 0) / 60,
            "activity" => suggestion(debt),
            "source" => "watch"
        };
    }

    function start() as Void {
        if (_timer != null) {
            return;
        }
        var v = Application.Storage.getValue(SYNC_KEY);
        if (v instanceof Array && v.size() >= 3) {
            var d = v[0];
            var s = v[1];
            var p = v[2];
            if ((d == null || d instanceof String) && s instanceof Number && p instanceof Number) {
                _seenDay = d;
                _seen = s;
                _pendingSec = p;
                var e = v.size() >= 4 ? v[3] : null;
                _seenEpoch = e instanceof String ? e : null;
            }
        }
        var t = new Timer.Timer();
        _timer = t;
        t.start(new Lang.Method(Sync, :pump), POLL_MS, true);
        pump();
    }

    function stop() as Void {
        var t = _timer;
        if (t != null) {
            t.stop();
        }
        _timer = null;
        _inFlight = false;
        save();
    }

    function save() as Void {
        Application.Storage.setValue(SYNC_KEY, [_seenDay, _seen, _pendingSec, _seenEpoch]);
    }

    function headersFor(apiKey as String) as Dictionary {
        var h = {
            "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON,
            "ngrok-skip-browser-warning" => "1"
        };
        if (!apiKey.equals("")) {
            h["x-api-key"] = apiKey;
        }
        return h;
    }

    function pump() as Void {
        var now = System.getTimer();
        if (_inFlight) {
            if (now - _inFlightSince < IN_FLIGHT_TIMEOUT_MS) {
                return;
            }
            _inFlight = false;
            fail(-408);
        }
        var body = payload(Ledger.balance(), _pendingSec, Ledger.multiplier(Engine.hour(), Engine.inBed()));
        var str = body.toString();
        var due = !str.equals(_lastPosted) || now - _lastPostMs >= HEARTBEAT_MS;
        var post = due && !_lastWasPost;
        var options = {
            :method => post ? Communications.HTTP_REQUEST_METHOD_POST : Communications.HTTP_REQUEST_METHOD_GET,
            :headers => headersFor(API_KEY),
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        _inFlight = true;
        _inFlightSince = now;
        _lastWasPost = post;
        _sending = str;
        try {
            Communications.makeWebRequest(SERVER_BASE + "/state", post ? body : null, options, new Lang.Method(Sync, :onResponse));
        } catch (e) {
            _inFlight = false;
            _online = false;
            fail(-9999);
        }
    }

    function onResponse(code as Number, data as Dictionary or String or Null) as Void {
        _inFlight = false;
        _lastCode = code;
        if (code != 200 || !(data instanceof Dictionary)) {
            _online = false;
            fail(code);
            return;
        }
        _fails = 0;
        var now = System.getTimer();
        _online = true;
        _lastOkMs = now;
        if (_lastWasPost) {
            _lastPosted = _sending;
            _lastPostMs = now;
        }
        var used = data["usedMinutesToday"];
        var day = data["usageDay"];
        if (used instanceof Number && day instanceof String) {
            var ep = data["usageEpoch"];
            var epoch = ep instanceof String ? ep : null;
            var r = usageDelta(_seenDay, _seen, _seenEpoch, day, used, epoch);
            var sd = _seenDay;
            var se = _seenEpoch;
            if (sd == null || !day.equals(sd) || used != _seen || (epoch != null && !epoch.equals(se))) {
                _seenDay = day;
                if (epoch != null) {
                    _seenEpoch = epoch;
                }
                _seen = r[1];
                _pendingSec += r[0] * 60;
                save();
            }
        } else {
            fail(-2);
        }
    }

    // Spends one pending second per call; call exactly once per tick.
    function takeSecond() as Boolean {
        var m = _manual;
        if (m != null) {
            return m;
        }
        if (_pendingSec > 0) {
            _pendingSec -= 1;
            return true;
        }
        return false;
    }

    function isScrolling() as Boolean {
        var m = _manual;
        if (m != null) {
            return m;
        }
        return _pendingSec > 0;
    }

    function isOnline() as Boolean {
        return _online && _lastOkMs >= 0 && (System.getTimer() - _lastOkMs) <= STALE_MS;
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

    function lastSyncAgoSec() as Number? {
        return _lastOkMs < 0 ? null : (System.getTimer() - _lastOkMs) / 1000;
    }

    function pendingSec() as Number {
        return _pendingSec;
    }
}
