// Why this exists: two-way sync with the laptop server. It pulls iPhone guarded-app usage (turned into
// scroll seconds) and pushes the watch's debt/credit so the iPhone can block apps while tax is owed.
import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;

// Real devices require HTTPS and route requests through the paired phone;
// only the simulator can reach http://127.0.0.1 directly.
// The public HTTPS tunnel URL goes here; a Cloudflare quick tunnel URL changes every time the tunnel restarts; for local-only testing use http://127.0.0.1:48217 with the simulator's HTTPS requirement setting unticked.
const SERVER_BASE = "https://bags-democrats-difference-pages.trycloudflare.com";
const API_KEY = "group16";
const POLL_MS = 4000;
const STALE_MS = 12000;
const HEARTBEAT_MS = 20000;
const MAX_CATCHUP_MIN = 120;
// Estimated pace, not measured: used only to word the "walk clears it" suggestion.
const WALK_M_PER_MIN = 80;
const REPS_MAX = 50;
const STAIRS_MAX = 15;
const EARN_MORE_MIN = 10;
const MAX_TEXT = 120;
const IN_FLIGHT_TIMEOUT_MS = 10000;
const SYNC_KEY = "sy";
const MAX_EVENT_SEC = 86400;
const MAX_REASON = 60;
const MIXED_REASON = "watch activity";

module Sync {
    var _on as Boolean = false;
    var _lastPumpMs as Number? = null;
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
    // Outbox: the server is the bank, so balance changes travel as events, each applied once per (session, id).
    var _session as String = "";
    var _nextEventId as Number = 1;
    var _unsent as Number = 0;
    var _unsentReason as String = "";
    var _inflight as Dictionary? = null;
    var _reqLedger as Boolean = false;
    // Last demo badge request acted on; _badgeSeen is false until the first reply after start.
    var _lastBadgeSeq as Number = 0;
    var _badgeSeen as Boolean = false;

    function base36(n as Number) as String {
        var digits = "0123456789abcdefghijklmnopqrstuvwxyz";
        var v = n < 0 ? -n : n;
        if (v == 0) {
            return "0";
        }
        var out = "";
        while (v > 0) {
            var r = v % 36;
            out = digits.substring(r, r + 1) + out;
            v = v / 36;
        }
        return out;
    }

    function ensureSession() as String {
        if (_session.equals("")) {
            _session = base36(Time.now().value()) + "-" + base36(System.getTimer());
        }
        return _session;
    }

    function resetOutbox() as Void {
        _session = "";
        _nextEventId = 1;
        _unsent = 0;
        _unsentReason = "";
        _inflight = null;
        _reqLedger = false;
    }

    // Every local balance change lands here; the first reason wins, mixed reasons become one label.
    function noteDelta(sec as Number, reason as String) as Void {
        if (sec == 0) {
            return;
        }
        if (_unsent == 0) {
            _unsentReason = reason;
        } else if (!reason.equals(_unsentReason)) {
            _unsentReason = MIXED_REASON;
        }
        _unsent += sec;
    }

    // Turns the accumulated delta into the next event unless one is already awaiting its ack.
    function startEvent() as Void {
        if (_inflight != null || _unsent == 0) {
            return;
        }
        var d = _unsent;
        if (d > MAX_EVENT_SEC) {
            d = MAX_EVENT_SEC;
        } else if (d < -MAX_EVENT_SEC) {
            d = -MAX_EVENT_SEC;
        }
        _inflight = {:id => _nextEventId, :delta => d, :reason => _unsentReason};
        _nextEventId += 1;
        _unsent -= d;
        if (_unsent == 0) {
            _unsentReason = "";
        }
        save();
    }

    function ackEvent() as Void {
        _inflight = null;
        save();
    }

    function eventBody(ev as Dictionary, pendingChargeSec as Number, activity as String) as Dictionary {
        var r = ev[:reason] as String;
        if (r.length() > MAX_REASON) {
            r = r.substring(0, MAX_REASON) as String;
        } else if (r.length() == 0) {
            r = MIXED_REASON;
        }
        return {
            "deltaSec" => ev[:delta] as Number,
            "reason" => r,
            "source" => "watch",
            "session" => ensureSession(),
            "eventId" => ev[:id] as Number,
            "activity" => activity,
            "pendingChargeSec" => pendingChargeSec
        };
    }

    // The watch mirrors the server: its balance plus whatever the server has not seen yet.
    function reconcile(serverBal as Number, inflightDelta as Number, unsent as Number) as Number {
        return serverBal + inflightDelta + unsent;
    }

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

    // Pace table: typical reps (or floors) per minute for the rep and floor kinds. Estimated, not measured.
    function pace(id as Symbol) as Float? {
        var t = {:jumpingJacks => 60.0, :squats => 25.0, :lunges => 20.0, :pushups => 20.0,
                 :dips => 15.0, :deadbug => 20.0, :birdDog => 20.0, :stairs => 4.0};
        return t[id] as Float?;
    }

    // One payoff option for `sec` seconds of credit: {:id, :min, :text}, or null if unusable.
    // `capped` applies the practicality limits (rep and floor counts, kind caps).
    function option(id as Symbol, sec as Number, capped as Boolean) as Dictionary? {
        var def = Catalog.get(id);
        if (def == null) {
            return null;
        }
        var unit = def[:unit] as Symbol;
        var label = (def[:label] as String).toLower();
        if (id == :walk) {
            var m = ceilDiv(sec, WALK_M_PER_MIN * Ledger.WALK_SEC_PER_KM / 1000.0);
            return {:id => id, :min => m, :text => "a " + m + " min walk"};
        }
        var rate = def[:rate] as Float;
        if (unit == :sec) {
            var cap = def[:cap] as Number?;
            if (capped && cap != null && cap < sec) {
                return null;
            }
            var t = ceilDiv(sec, rate * 60.0);
            return {:id => id, :min => t, :text => t + " min " + label};
        }
        var p = pace(id);
        if (p == null) {
            return null;
        }
        var n = ceilDiv(sec, rate);
        var floors = unit == :floor;
        if (capped && n > (floors ? STAIRS_MAX : REPS_MAX)) {
            return null;
        }
        return {:id => id, :min => ceilDiv(sec, rate * p), :text => floors ? n + " floors of stairs" : n + " " + label};
    }

    // The two fastest options for `sec` seconds of credit (second may be null; first is null only if nothing qualifies).
    function rank(sec as Number) as Array<Dictionary?> {
        var all = Catalog.all();
        var ids = [] as Array<Symbol>;
        for (var i = 0; i < all.size(); i++) {
            var d = all[i];
            var g = d[:group];
            if ((g == :exercise || g == :chore) && !(d[:daily] as Boolean) && d[:detector] != :outdoors && d[:detector] != :calm) {
                ids.add(d[:id] as Symbol);
            }
        }
        ids.add(:walk);
        var b1 = null as Dictionary?;
        var b2 = null as Dictionary?;
        for (var i = 0; i < ids.size(); i++) {
            var o = option(ids[i], sec, true);
            if (o == null) {
                continue;
            }
            if (b1 == null || (o[:min] as Number) < (b1[:min] as Number)) {
                b2 = b1;
                b1 = o;
            } else if (b2 == null || (o[:min] as Number) < (b2[:min] as Number)) {
                b2 = o;
            }
        }
        return [b1, b2] as Array<Dictionary?>;
    }

    function suggestion(debtSec as Number) as String {
        var e = rank(EARN_MORE_MIN * 60)[0];
        var earn = e == null ? "" : e[:text] as String;
        if (debtSec <= 0) {
            return "Earn " + EARN_MORE_MIN + " min to scroll: " + earn;
        }
        var r = rank(debtSec);
        var b1 = r[0];
        var b2 = r[1];
        if (b1 == null) {
            return "";
        }
        var tail = e == null ? "" : ". +" + EARN_MORE_MIN + " min to scroll: " + earn;
        var one = b1[:text] + " clears it";
        var s = b2 == null ? one + tail : b1[:text] + " or " + b2[:text] + " clears it" + tail;
        if (s.length() > MAX_TEXT) {
            s = one + tail;
        }
        return s.length() > MAX_TEXT ? one : s;
    }

    function payload(balanceSec as Number, pendingSec as Number, mult as Number) as Dictionary {
        var eff = effBalance(balanceSec, pendingSec, mult);
        return {
            "activity" => suggestion(eff < 0 ? -eff : 0),
            "pendingChargeSec" => pendingSec * mult
        };
    }

    // Returns [award id String or null, new last seq]. A first reply with nothing stored is an old request: store only.
    function badgeToAward(lastSeq as Number, firstSync as Boolean, cmd as Dictionary?) as Array {
        if (cmd == null) {
            return [null, lastSeq];
        }
        var seq = cmd["seq"];
        var id = cmd["id"];
        if (!(seq instanceof Number) || !(id instanceof String) || seq <= lastSeq) {
            return [null, lastSeq];
        }
        if (firstSync || Badges.strToId(id) == null) {
            return [null, seq];
        }
        return [id, seq];
    }

    // Loads a stored "sy" value; older 3 and 4 element shapes keep working.
    function restore(v as Object?) as Void {
        if (!(v instanceof Array) || v.size() < 3) {
            return;
        }
        var d = v[0];
        var s = v[1];
        var p = v[2];
        if (!((d == null || d instanceof String) && s instanceof Number && p instanceof Number)) {
            return;
        }
        _seenDay = d;
        _seen = s;
        _pendingSec = p;
        var e = v.size() >= 4 ? v[3] : null;
        _seenEpoch = e instanceof String ? e : null;
        var bs = v.size() >= 12 ? v[11] : null;
        _lastBadgeSeq = bs instanceof Number ? bs : 0;
        if (v.size() < 11) {
            return;
        }
        var ses = v[4];
        var nid = v[5];
        var uns = v[6];
        var unr = v[7];
        if (ses instanceof String && nid instanceof Number && nid >= 1 && uns instanceof Number && unr instanceof String) {
            _session = ses;
            _nextEventId = nid;
            _unsent = uns;
            _unsentReason = unr;
            var iid = v[8];
            var idl = v[9];
            var irs = v[10];
            _inflight = (iid instanceof Number && idl instanceof Number && irs instanceof String) ? {:id => iid, :delta => idl, :reason => irs} : null;
        }
    }

    function start() as Void {
        if (_on) {
            return;
        }
        restore(Application.Storage.getValue(SYNC_KEY));
        ensureSession();
        _on = true;
        _lastPumpMs = System.getTimer();
        pump();
    }

    // First call or a clock wrap (now < last) is due; otherwise wait POLL_MS.
    function pollDue(lastMs as Number?, nowMs as Number) as Boolean {
        return lastMs == null || nowMs < lastMs || nowMs - lastMs >= POLL_MS;
    }

    // Engine's 1 s tick drives polling; Sync owns no Timer.
    function tick(nowMs as Number) as Void {
        if (_on && pollDue(_lastPumpMs, nowMs)) {
            _lastPumpMs = nowMs;
            pump();
        }
    }

    function stop() as Void {
        _on = false;
        _inFlight = false;
        save();
    }

    function save() as Void {
        var inf = _inflight;
        Application.Storage.setValue(SYNC_KEY, [_seenDay, _seen, _pendingSec, _seenEpoch, _session, _nextEventId, _unsent, _unsentReason,
            inf == null ? null : inf[:id], inf == null ? null : inf[:delta], inf == null ? null : inf[:reason], _lastBadgeSeq]);
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
        var str = (body["activity"] as String) + "|" + (body["pendingChargeSec"] as Number);
        startEvent();
        var ev = _inflight;
        var post = true;
        var path = "/ledger";
        if (ev != null) {
            body = eventBody(ev, body["pendingChargeSec"] as Number, body["activity"] as String);
        } else {
            path = "/state";
            var due = !str.equals(_lastPosted) || now - _lastPostMs >= HEARTBEAT_MS;
            post = due && !_lastWasPost;
            _lastWasPost = post;
        }
        _reqLedger = ev != null;
        var options = {
            :method => post ? Communications.HTTP_REQUEST_METHOD_POST : Communications.HTTP_REQUEST_METHOD_GET,
            :headers => headersFor(API_KEY),
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        _inFlight = true;
        _inFlightSince = now;
        _sending = str;
        try {
            Communications.makeWebRequest(SERVER_BASE + path, post ? body : null, options, new Lang.Method(Sync, :onResponse));
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
        if (_reqLedger) {
            ackEvent();
        } else if (_lastWasPost) {
            _lastPosted = _sending;
            _lastPostMs = now;
        }
        var bal = data["balanceSec"];
        if (bal instanceof Number) {
            var inf = _inflight;
            var local = reconcile(bal, inf == null ? 0 : inf[:delta] as Number, _unsent);
            if (local != Ledger.balance()) {
                Ledger.applyServerBalance(local);
            }
        }
        var cmd = data["badgeCommand"];
        var ba = badgeToAward(_lastBadgeSeq, !_badgeSeen && _lastBadgeSeq == 0, cmd instanceof Dictionary ? cmd : null);
        _badgeSeen = true;
        if (ba[1] != _lastBadgeSeq) {
            _lastBadgeSeq = ba[1] as Number;
            var bid = ba[0];
            if (bid instanceof String) {
                Badges.demoAward(Badges.strToId(bid) as Symbol);
            }
            save();
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
