// Why this exists: Thumb Tax's own history (minutes scrolled, taxed, earned back) for the trend pages.
// Until the first real scroll second or earn is recorded, every series returns the demo constants below.
// Stored seconds are reported as minutes rounded down. Night here is 20:00 to 08:00 and is exposure only;
// taxed figures are the seconds the bank (Ledger) actually charged, recorded as they happen.
import Toybox.Application;
import Toybox.Lang;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.UserProfile;

module Records {
    const NIGHT_RATE = 2;
    const STORE_SIZE = 18;
    const SCROLL_NIGHT_MIN = 30;
    const LAST_NIGHT_START_HOUR = 20;
    const NIGHT_FROM = 20;
    const NIGHT_TO = 8;
    const SESSIONS_MAX = 40;
    const DEFAULT_RESTING_HR = 60;
    const SPO2_WINDOW_SEC = 43200;
    const KEY = "rc_d";

    const DEMO_WEEK_DAY_MIN = [22, 35, 18, 40, 28, 15, 12] as Array<Number>;
    const DEMO_WEEK_NIGHT_MIN = [45, 30, 55, 20, 60, 25, 38] as Array<Number>;
    const DEMO_WEEK_EARNED_MIN = [10, 15, 0, 20, 5, 30, 15] as Array<Number>;
    const DEMO_WEEK_HR_LIFT = [9, 6, 11, 4, 12, 5, 8] as Array<Number>;
    const DEMO_WEEK_SPO2 = [94, 96, 93, 97, 93, 96, 95] as Array<Number>;
    const DEMO_LAST_WEEK_TAXED = 520;
    const DEMO_TODAY_HOURLY_MIN = [12, 8, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 5, 2, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0] as Array<Number>;
    const DEMO_TODAY_EARNED_HOURLY = [0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 0, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0] as Array<Number>;
    const DEMO_LAST_NIGHT_BINS = [0, 0, 10, 8, 12, 8, 0, 0, 0, 0, 0, 0] as Array<Number>;
    const DEMO_TODAY_SESSIONS = [[0, 12], [60, 68], [480, 483], [720, 725], [780, 782], [1020, 1022]] as Array<Array<Number>>;

    var _loaded as Boolean = false;
    var _real as Boolean = false;
    var _dayKey as Number = 0;
    // Week rings, oldest first, last = today. Seconds, except _spo2 (percent).
    var _day as Array<Number> = [];
    var _night as Array<Number> = [];
    var _earn as Array<Number> = [];
    var _hrSum as Array<Number> = [];
    var _hrN as Array<Number> = [];
    var _spo2 as Array<Number> = [];
    // Taxed minutes of the days that fell off the ring, newest last; their sum is last week.
    var _prev as Array<Number> = [];
    var _hourly as Array<Number> = [];
    var _earnHourly as Array<Number> = [];
    // Night that ends this morning (12 hourly bins from 20:00), and tonight's evening part waiting for midnight.
    var _bins as Array<Number> = [];
    var _nextBins as Array<Number> = [];
    var _pend as Array<Number> = [];
    var _sessions as Array<Array<Number>> = [];
    var _open as Number = -1;
    // Seconds the bank charged: per week day and per hour of today.
    var _chDay as Array<Number> = [];
    var _chHourly as Array<Number> = [];
    // Minute of the last recorded second, so inSession needs no clock call.
    var _nowMin as Number = 0;
    var _spo2Day as Number = -1;

    function zeros(n as Number) as Array<Number> {
        var a = [] as Array<Number>;
        for (var i = 0; i < n; i++) {
            a.add(0);
        }
        return a;
    }

    function dayKey() as Number {
        var c = System.getClockTime();
        return (Time.now().value() + c.timeZoneOffset + c.dst) / 86400;
    }

    function nowMinute() as Number {
        var c = System.getClockTime();
        return c.hour * 60 + c.min;
    }

    // In-memory state only; load() uses it so launching never touches stored data.
    function clear() as Void {
        _loaded = true;
        _real = false;
        _dayKey = dayKey();
        _day = zeros(7);
        _night = zeros(7);
        _earn = zeros(7);
        _hrSum = zeros(7);
        _hrN = zeros(7);
        _spo2 = zeros(7);
        _prev = [];
        _hourly = zeros(24);
        _earnHourly = zeros(24);
        _bins = zeros(12);
        _nextBins = zeros(4);
        _pend = zeros(3);
        _sessions = [];
        _open = -1;
        _chDay = zeros(7);
        _chHourly = zeros(24);
        _nowMin = 0;
        _spo2Day = -1;
    }

    // Wipes memory and the stored copy; for tests and Ledger.reset.
    function reset() as Void {
        clear();
        Application.Storage.deleteValue(KEY);
    }

    // Test helper: forces the next load() to read Storage again.
    function unload() as Void {
        _loaded = false;
    }

    function load() as Void {
        if (_loaded) {
            return;
        }
        clear();
        var d = Application.Storage.getValue(KEY) as Array?;
        if (d == null || d.size() != STORE_SIZE) {
            return;
        }
        _dayKey = d[0] as Number;
        _real = (d[1] as Number) == 1;
        _day = d[2] as Array<Number>;
        _night = d[3] as Array<Number>;
        _earn = d[4] as Array<Number>;
        _hrSum = d[5] as Array<Number>;
        _hrN = d[6] as Array<Number>;
        _spo2 = d[7] as Array<Number>;
        _prev = d[8] as Array<Number>;
        _hourly = d[9] as Array<Number>;
        _earnHourly = d[10] as Array<Number>;
        _bins = d[11] as Array<Number>;
        _nextBins = d[12] as Array<Number>;
        _pend = d[13] as Array<Number>;
        _sessions = d[14] as Array<Array<Number>>;
        _open = d[15] as Number;
        _chDay = d[16] as Array<Number>;
        _chHourly = d[17] as Array<Number>;
    }

    function save() as Void {
        load();
        Application.Storage.setValue(KEY, [_dayKey, _real ? 1 : 0, _day, _night, _earn, _hrSum, _hrN, _spo2,
            _prev, _hourly, _earnHourly, _bins, _nextBins, _pend, _sessions, _open, _chDay, _chHourly]);
    }

    function shiftLeft(a as Array<Number>) as Array<Number> {
        var out = a.slice(1, null) as Array<Number>;
        out.add(0);
        return out;
    }

    // Average of the last 12 hours of SpO2 samples, 0 when the watch has none.
    function fetchSpo2() as Number {
        if (!(SensorHistory has :getOxygenSaturationHistory)) {
            return 0;
        }
        var it = SensorHistory.getOxygenSaturationHistory({
            :period => new Time.Duration(SPO2_WINDOW_SEC),
            :order => SensorHistory.ORDER_NEWEST_FIRST
        }) as SensorHistory.SensorHistoryIterator?;
        if (it == null) {
            return 0;
        }
        var total = 0.0;
        var n = 0;
        var s = it.next();
        while (s != null) {
            var v = s.data;
            if (v != null) {
                total += v;
                n += 1;
            }
            s = it.next();
        }
        return n > 0 ? (total / n + 0.5).toNumber() : 0;
    }

    function rollDay() as Void {
        var days = dayKey() - _dayKey;
        if (days <= 0) {
            return;
        }
        _dayKey += days;
        if (days > 7) {
            days = 7;
        }
        for (var s = 0; s < days; s++) {
            _prev.add(_chDay[0]);
            if (_prev.size() > 7) {
                _prev = _prev.slice(_prev.size() - 7, null) as Array<Number>;
            }
            _chDay = shiftLeft(_chDay);
            _day = shiftLeft(_day);
            _night = shiftLeft(_night);
            _earn = shiftLeft(_earn);
            _hrSum = shiftLeft(_hrSum);
            _hrN = shiftLeft(_hrN);
            _spo2 = shiftLeft(_spo2);
            // Last evening's scrolling becomes the new morning's night.
            _night[6] = _pend[0];
            _hrSum[6] = _pend[1];
            _hrN[6] = _pend[2];
            _bins = _nextBins.slice(0, null) as Array<Number>;
            _bins.addAll(zeros(8));
            _nextBins = zeros(4);
            _pend = zeros(3);
        }
        _spo2[6] = fetchSpo2();
        _spo2Day = _dayKey;
        _chHourly = zeros(24);
        _hourly = zeros(24);
        _earnHourly = zeros(24);
        _sessions = [];
        if (_open >= 0) {
            _open = 0;
        }
    }

    function ready() as Void {
        load();
        rollDay();
        // Started mid-day: show last night's average once, not after the first midnight.
        if (_spo2Day != _dayKey) {
            _spo2Day = _dayKey;
            if (_spo2[6] == 0) {
                _spo2[6] = fetchSpo2();
            }
        }
    }

    // chargedSec is what Ledger.chargeScroll returned for this second.
    function addScrollSecond(hr as Number?, chargedSec as Number) as Void {
        ready();
        _real = true;
        var c = System.getClockTime();
        var h = c.hour;
        _nowMin = c.hour * 60 + c.min;
        _hourly[h] += 1;
        _chHourly[h] += chargedSec;
        _chDay[6] += chargedSec;
        if (h >= NIGHT_FROM) {
            _pend[0] += 1;
            _nextBins[h - NIGHT_FROM] += 1;
            if (hr != null) {
                _pend[1] += hr;
                _pend[2] += 1;
            }
        } else if (h < NIGHT_TO) {
            _night[6] += 1;
            _bins[h + 24 - NIGHT_FROM] += 1;
            if (hr != null) {
                _hrSum[6] += hr;
                _hrN[6] += 1;
            }
        } else {
            _day[6] += 1;
        }
    }

    function openSession() as Void {
        ready();
        if (_open < 0) {
            _open = nowMinute();
            _nowMin = _open;
        }
    }

    function closeSession() as Void {
        ready();
        if (_open < 0) {
            return;
        }
        _nowMin = nowMinute();
        _sessions.add([_open, _nowMin]);
        if (_sessions.size() > SESSIONS_MAX) {
            _sessions = _sessions.slice(_sessions.size() - SESSIONS_MAX, null) as Array<Array<Number>>;
        }
        _open = -1;
    }

    function addEarned(sec as Number) as Void {
        ready();
        _real = true;
        _earnHourly[System.getClockTime().hour] += sec;
        _earn[6] += sec;
    }

    function isDemo() as Boolean {
        load();
        return !_real;
    }

    function minutes(a as Array<Number>) as Array<Number> {
        var out = [] as Array<Number>;
        for (var i = 0; i < a.size(); i++) {
            out.add(a[i] / 60);
        }
        return out;
    }

    function weekDayMin() as Array<Number> {
        ready();
        return _real ? minutes(_day) : DEMO_WEEK_DAY_MIN;
    }

    function weekNightMin() as Array<Number> {
        ready();
        return _real ? minutes(_night) : DEMO_WEEK_NIGHT_MIN;
    }

    function weekEarnedMin() as Array<Number> {
        ready();
        return _real ? minutes(_earn) : DEMO_WEEK_EARNED_MIN;
    }

    // Average heart rate while scrolling at night, above the resting rate; 0 when there is none.
    function weekHrLift() as Array<Number> {
        ready();
        if (!_real) {
            return DEMO_WEEK_HR_LIFT;
        }
        var rest = DEFAULT_RESTING_HR;
        var p = UserProfile.getProfile();
        if (p != null && p.restingHeartRate != null) {
            rest = p.restingHeartRate as Number;
        }
        var out = [] as Array<Number>;
        for (var i = 0; i < 7; i++) {
            var lift = (_hrN[i] > 0) ? _hrSum[i] / _hrN[i] - rest : 0;
            out.add(lift > 0 ? lift : 0);
        }
        return out;
    }

    function weekSpo2() as Array<Number> {
        ready();
        return _real ? _spo2 : DEMO_WEEK_SPO2;
    }

    function lastWeekTaxed() as Number {
        ready();
        return _real ? sum(_prev) / 60 : DEMO_LAST_WEEK_TAXED;
    }

    function todayHourlyMin() as Array<Number> {
        ready();
        return _real ? minutes(_hourly) : DEMO_TODAY_HOURLY_MIN;
    }

    function todayEarnedHourly() as Array<Number> {
        ready();
        return _real ? minutes(_earnHourly) : DEMO_TODAY_EARNED_HOURLY;
    }

    function lastNightBins() as Array<Number> {
        ready();
        return _real ? minutes(_bins) : DEMO_LAST_NIGHT_BINS;
    }

    // A session still open is included up to the current minute.
    function todaySessions() as Array<Array<Number>> {
        ready();
        if (!_real) {
            return DEMO_TODAY_SESSIONS;
        }
        var out = _sessions.slice(0, null) as Array<Array<Number>>;
        if (_open >= 0) {
            out.add([_open, nowMinute()]);
        }
        return out;
    }

    function isNightHour(h as Number) as Boolean {
        return h >= 22 || h < 6;
    }

    // Real mode: minutes the bank charged. Demo mode: the demo formula.
    function taxedOn(i as Number) as Number {
        ready();
        if (_real) {
            return _chDay[i] / 60;
        }
        return DEMO_WEEK_DAY_MIN[i] + DEMO_WEEK_NIGHT_MIN[i] * NIGHT_RATE;
    }

    function weekTaxed() as Number {
        ready();
        if (_real) {
            return sum(_chDay) / 60;
        }
        var t = 0;
        for (var i = 0; i < 7; i++) {
            t += taxedOn(i);
        }
        return t;
    }

    function todayTaxed() as Number {
        ready();
        if (_real) {
            return sum(_chHourly) / 60;
        }
        var t = 0;
        for (var h = 0; h < 24; h++) {
            t += DEMO_TODAY_HOURLY_MIN[h] * (isNightHour(h) ? NIGHT_RATE : 1);
        }
        return t;
    }

    // Called up to 1440 times per draw: no rollDay, clock or slicing here; _nowMin is kept by the 1 Hz recorder.
    function inSession(minute as Number) as Boolean {
        var sessions = isDemo() ? DEMO_TODAY_SESSIONS : _sessions;
        for (var i = 0; i < sessions.size(); i++) {
            var s = sessions[i];
            if (minute >= s[0] && minute <= s[1]) {
                return true;
            }
        }
        return !isDemo() && _open >= 0 && minute >= _open && minute <= _nowMin;
    }

    function sum(a as Array<Number>) as Number {
        var t = 0;
        for (var i = 0; i < a.size(); i++) {
            t += a[i];
        }
        return t;
    }

    // One-letter day names for the last 7 days, ending today.
    function weekLabels() as Array<String> {
        var names = ["S", "M", "T", "W", "T", "F", "S"];
        var today = Gregorian.info(Time.now(), Time.FORMAT_SHORT).day_of_week as Number;
        var out = [] as Array<String>;
        for (var i = 0; i < 7; i++) {
            out.add(names[(today - 1 - (6 - i) + 14) % 7]);
        }
        return out;
    }

    // Full day name for a week index, used in insights.
    function dayName(i as Number) as String {
        var names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
        var today = Gregorian.info(Time.now(), Time.FORMAT_SHORT).day_of_week as Number;
        return names[(today - 1 - (6 - i) + 14) % 7];
    }

    // "2h 05m" or "38 min".
    function fmtMin(m as Number) as String {
        var a = (m < 0) ? -m : m;
        if (a < 60) {
            return a + " min";
        }
        return (a / 60) + "h " + (a % 60).format("%02d") + "m";
    }
}
