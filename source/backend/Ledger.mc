// The time bank: one signed balance in seconds, plus today's stats and a short history.
// All exchange rates live here so there is a single place to tune them.
import Toybox.Application;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

module Ledger {
    const PUSHUP_SEC = 30;
    const FLOOR_SEC = 120;
    const WALK_SEC_PER_KM = 600;
    const CLIMB_SEC_PER_M = 12;
    const READING_RATIO = 0.5;
    const DAY_MULT = 1;
    const NIGHT_MULT = 2;
    const BED_MULT = 3;
    const NIGHT_START_HOUR = 22;
    const NIGHT_END_HOUR = 6;
    const HISTORY_MAX = 20;

    var _loaded as Boolean = false;
    var _balance as Number = 0;
    var _dayKey as Number = 0;
    var _scrollDay as Number = 0;
    var _scrollNight as Number = 0;
    var _fee as Number = 0;
    var _earned as Number = 0;
    var _entries as Number = 0;
    // Each entry is [t, delta, reason]; plain arrays because Storage cannot hold Symbol keys.
    var _history as Array = [];

    function today() as Number {
        var i = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        return i.year * 10000 + i.month * 100 + i.day;
    }

    function clearToday() as Void {
        _scrollDay = 0;
        _scrollNight = 0;
        _fee = 0;
        _earned = 0;
        _entries = 0;
    }

    function rollDay() as Void {
        var k = today();
        if (k != _dayKey) {
            _dayKey = k;
            clearToday();
        }
    }

    function reset() as Void {
        _loaded = true;
        _balance = 0;
        _dayKey = today();
        clearToday();
        _history = [];
    }

    function load() as Void {
        if (_loaded) {
            return;
        }
        reset();
        var s = Application.Storage;
        var b = s.getValue("lg_bal");
        if (b == null) {
            return;
        }
        _balance = b as Number;
        var h = s.getValue("lg_hist");
        if (h != null) {
            _history = h as Array;
        }
        var d = s.getValue("lg_day") as Array?;
        if (d != null && d.size() == 6 && d[0] == _dayKey) {
            _scrollDay = d[1] as Number;
            _scrollNight = d[2] as Number;
            _fee = d[3] as Number;
            _earned = d[4] as Number;
            _entries = d[5] as Number;
        }
    }

    function save() as Void {
        load();
        var s = Application.Storage;
        s.setValue("lg_bal", _balance);
        s.setValue("lg_hist", _history);
        s.setValue("lg_day", [_dayKey, _scrollDay, _scrollNight, _fee, _earned, _entries]);
    }

    function balance() as Number {
        load();
        return _balance;
    }

    function isOverdrawn() as Boolean {
        load();
        return _balance < 0;
    }

    function isNight(hour as Number) as Boolean {
        return hour >= NIGHT_START_HOUR || hour < NIGHT_END_HOUR;
    }

    function multiplier(hour as Number, inBed as Boolean) as Number {
        if (!isNight(hour)) {
            return DAY_MULT;
        }
        return inBed ? BED_MULT : NIGHT_MULT;
    }

    function chargeScroll(seconds as Number, hour as Number, inBed as Boolean) as Number {
        load();
        rollDay();
        var m = multiplier(hour, inBed);
        var charged = seconds * m;
        _balance -= charged;
        if (m > DAY_MULT) {
            _scrollNight += seconds;
        } else {
            _scrollDay += seconds;
        }
        _fee += charged - seconds;
        return charged;
    }

    function addHistory(delta as Number, reason as String) as Void {
        rollDay();
        _history.add([Time.now().value(), delta, reason]);
        if (_history.size() > HISTORY_MAX) {
            _history = _history.slice(_history.size() - HISTORY_MAX, null);
        }
        _entries += 1;
    }

    function closeScrollSession(seconds as Number, chargedSec as Number, night as Boolean) as Void {
        if (chargedSec <= 0) {
            return;
        }
        load();
        addHistory(-chargedSec, night ? "night scroll" : "scroll");
    }

    function round(x as Float) as Number {
        return (x + 0.5).toNumber();
    }

    function earn(kind as Symbol, amount as Numeric) as Number {
        var sec = 0;
        var why = "";
        if (kind == :pushups) {
            sec = amount.toNumber() * PUSHUP_SEC;
            why = "push-ups x" + amount.toNumber();
        } else if (kind == :floors) {
            sec = amount.toNumber() * FLOOR_SEC;
            why = "stairs " + amount.toNumber() + " floors";
        } else if (kind == :walkM) {
            sec = round(amount.toFloat() / 1000.0 * WALK_SEC_PER_KM);
            why = "walk " + (amount.toFloat() / 1000.0).format("%.1f") + " km";
        } else if (kind == :climbM) {
            sec = round(amount.toFloat() * CLIMB_SEC_PER_M);
            why = "climb " + amount.toNumber() + " m";
        } else if (kind == :readingSec) {
            sec = round(amount.toFloat() * READING_RATIO);
            why = "reading " + (amount.toNumber() / 60) + " min";
        } else {
            return 0;
        }
        if (sec <= 0) {
            return 0;
        }
        load();
        rollDay();
        _balance += sec;
        _earned += sec;
        addHistory(sec, why);
        save();
        return sec;
    }

    function stats() as Dictionary {
        load();
        rollDay();
        return {
            :scrollDaySec => _scrollDay,
            :scrollNightSec => _scrollNight,
            :feeSec => _fee,
            :earnedSec => _earned,
            :entries => _entries
        };
    }

    function history() as Array {
        load();
        var out = [];
        for (var i = 0; i < _history.size(); i++) {
            var e = _history[i] as Array;
            out.add({:t => e[0], :delta => e[1], :reason => e[2]});
        }
        return out;
    }
}
