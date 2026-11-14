// Habit badges the watch can verify itself: clean days, streaks, screen-free windows and monthly savings.
// Engine feeds onTick once per second; day, window and month closes are detected from the clock.
// Every rule is a pure function with explicit inputs so the tests can drive it without waiting for midnight.
import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.UserProfile;

module Badges {
    const MIN_MONITORED_SEC = 3600;
    const WAKE_DEFAULT_MIN = 420;
    const SLEEP_DEFAULT_MIN = 1380;
    const WINDOW_MIN = 60;
    const WINDOW_NEED_SEC = 2700;
    const SUNDAY_END_MIN = 720;
    const SUNDAY_NEED_PCT = 75;
    const SUNDAYS_NEEDED = 4;
    const WEEK_DAYS = 7;
    const RECORD_MIN_BEST = 3;
    const DEEP_WORK_SEC = 6000;
    const FONDO_SEC = 86400;
    const FONDO_GAP_SEC = 600;
    const LIGHT_DAY_MAX_MIN = 30;
    const DETOUR_SESSION_MAX_SEC = 10;
    const DETOUR_WINDOW_SEC = 60;
    const LEGEND_MIN_ACTIVITY = 10;
    const LEGEND_COOLDOWN_SEC = 2592000;
    const RING_DAYS = 30;
    const DAY_MIN = 1440;
    const OFFLINE_TOL_SEC = 3;
    const MONTH_MIN_HOURS = 20.0;
    const HIST_DAYS = 9;
    const MONTHS_KEPT = 5;
    const PRIOR_MONTHS = 3;
    const SATURDAY = 7;
    const SUNDAY = 1;
    const MILESTONE_DAYS = [100, 365, 500, 1000] as Array<Number>;
    const MILESTONE_IDS = [:days100, :days365, :days500, :days1000] as Array<Symbol>;
    const RECLAIM_HOURS = [10, 25, 50] as Array<Number>;
    const RECLAIM_IDS = [:reclaimed10h, :reclaimed25h, :reclaimed50h] as Array<Symbol>;

    // Fixed order: counts and last-earned times are stored by position, unseen ids by string.
    const IDS = [:firstClose, :perfectWeek, :longestStreak, :days100, :days365, :days500, :days1000,
        :screenFreeMorning, :digitalSunset, :perfectAnalogWeek, :deepWork100, :analogFondo, :weekendOffGrid,
        :reclaimed10h, :reclaimed25h, :reclaimed50h, :localLegend, :dopamineDetour, :festiveUnplug,
        :sundayReset] as Array<Symbol>;
    const STRS = ["fc", "pw", "ls", "d1", "d3", "d5", "dk", "sm", "ds", "pa", "dw", "af", "wo",
        "r1", "r2", "r5", "ll", "dd", "fu", "sr"] as Array<String>;
    // name, description, repeatable
    const DEFS = [
        ["First Clean Close", "Your first clean day.", false],
        ["Perfect Week", "7 clean days in a row.", true],
        ["Longest Streak", "Beat your best clean streak.", true],
        ["100 Clean Days", "100 clean days in total.", false],
        ["365 Clean Days", "365 clean days in total.", false],
        ["500 Clean Days", "500 clean days in total.", false],
        ["1,000 Clean Days", "1,000 clean days in total.", false],
        ["Screen-Free Morning", "No scrolling for an hour after waking.", true],
        ["Digital Sunset", "No scrolling for an hour before bed.", true],
        ["Perfect Analog Week", "7 days both clean and sunset-clean.", true],
        ["Deep Work 100", "100 awake minutes without scrolling.", true],
        ["Analog Fondo", "24 hours without scrolling.", true],
        ["Weekend Off-Grid", "A weekend under 30 min scrolled a day.", true],
        ["Time Reclaimed: 10 h", "Scrolled 10 h less than usual last month.", true],
        ["Time Reclaimed: 25 h", "Scrolled 25 h less than usual last month.", true],
        ["Time Reclaimed: 50 h", "Scrolled 50 h less than usual last month.", true],
        ["Local Legend", "More activity sessions than scroll sessions in 30 days.", true],
        ["Dopamine Detour", "A short scroll, then you got moving.", true],
        ["The Festive Unplug", "Dec 24 to Jan 1 under 30 min a day.", true],
        ["Sunday Reset", "4 phone-free Sunday mornings in a month.", true]
    ] as Array<Array>;

    var _loaded as Boolean = false;
    var _dayKey as Number = 0;
    var _y as Number = 0;
    var _m as Number = 0;
    var _d as Number = 0;
    var _wk as Number = 0;
    var _wake as Number = WAKE_DEFAULT_MIN;
    var _sleep as Number = SLEEP_DEFAULT_MIN;
    var _mon as Number = 0;
    var _scr as Number = 0;
    var _ovd as Number = 0;
    // Monitored and scrolled seconds inside the morning, sunset and sunday windows.
    var _w as Array<Number> = [0, 0, 0, 0, 0, 0];
    // Window done flags (morning, sunset, sunday), sunset passed, deep work awarded today.
    var _fl as Array<Number> = [0, 0, 0, 0, 0];
    var _lastTick as Number = 0;
    var _dwRun as Number = 0;
    var _foRun as Number = 0;
    var _gap as Number = 0;
    var _streak as Number = 0;
    var _best as Number = 0;
    var _base as Number = 0;
    var _clean as Number = 0;
    var _analog as Number = 0;
    var _sunMonth as Number = 0;
    var _sunCount as Number = 0;
    // Daily [scrollSessions, creditedActivitySessions] flat, slot = dayKey % RING_DAYS.
    var _ring as Array<Number> = [];
    // Closed days, oldest first: [clean, sunset, scrolledMin, monitoredSec, weekday, month, day].
    var _hist as Array<Array<Number>> = [];
    var _mKey as Array<Number> = [];
    var _mSec as Array<Number> = [];
    var _mMon as Array<Number> = [];
    // Local day key cached per clock minute so the 1 Hz tick does not rebuild the date.
    var _cMin as Number = -1;
    var _cKey as Number = 0;
    var _cnt as Array<Number> = [];
    var _lastAt as Array<Number> = [];
    var _unseen as Array<String> = [];
    var _buzz as Boolean = false;
    var _detourAt as Number = 0;
    var _detourDur as Number = 0;

    // ---- pure rules ----

    function isCleanDay(monitoredSec as Number, overdraftSec as Number) as Boolean {
        return overdraftSec == 0 && monitoredSec >= MIN_MONITORED_SEC;
    }

    // Returns [streak, best, runBase, beatRecord]; runBase is the best when this run started.
    function evalStreak(streak as Number, best as Number, runBase as Number, clean as Boolean) as Array<Number> {
        if (!clean) {
            return [0, best, runBase, 0];
        }
        var base = streak == 0 ? best : runBase;
        var s = streak + 1;
        var beat = (s == base + 1 && base >= RECORD_MIN_BEST) ? 1 : 0;
        return [s, s > best ? s : best, base, beat];
    }

    function windowClean(monitoredSec as Number, scrolledSec as Number, needSec as Number) as Boolean {
        return scrolledSec == 0 && monitoredSec >= needSec;
    }

    function lightDay(scrolledMin as Number, monitoredSec as Number) as Boolean {
        return scrolledMin <= LIGHT_DAY_MAX_MIN && monitoredSec >= MIN_MONITORED_SEC;
    }

    function isFestiveDay(month as Number, day as Number) as Boolean {
        return (month == 12 && day >= 24) || (month == 1 && day == 1);
    }

    function festiveRun(hist as Array<Array<Number>>) as Boolean {
        if (hist.size() < HIST_DAYS) {
            return false;
        }
        for (var i = hist.size() - HIST_DAYS; i < hist.size(); i++) {
            var e = hist[i];
            if (!isFestiveDay(e[5], e[6]) || !lightDay(e[2], e[3])) {
                return false;
            }
        }
        return true;
    }

    function weekendOk(sat as Array<Number>, sun as Array<Number>) as Boolean {
        return sat[4] == SATURDAY && sun[4] == SUNDAY && lightDay(sat[2], sat[3]) && lightDay(sun[2], sun[3]);
    }

    // Returns 0, 10, 25 or 50: hours saved by scroll rate (scrolled per monitored hour) against the
    // prior months, scaled to the month's own monitored hours. Under 20 monitored hours earns nothing.
    function reclaimedTier(prevScrH as Float, prevMonH as Float, priorScrH as Float, priorMonH as Float) as Number {
        if (prevMonH < MONTH_MIN_HOURS || priorMonH < MONTH_MIN_HOURS) {
            return 0;
        }
        var saved = (priorScrH / priorMonH - prevScrH / prevMonH) * prevMonH;
        var tier = 0;
        for (var i = 0; i < RECLAIM_HOURS.size(); i++) {
            if (saved >= RECLAIM_HOURS[i].toFloat()) {
                tier = RECLAIM_HOURS[i];
            }
        }
        return tier;
    }

    // Seconds counted offline between two ticks. The 1000 ms timer drifts, so up to 3 s is still monitoring.
    function offlineGap(prevTick as Number, now as Number) as Number {
        return (prevTick > 0 && now - prevTick > OFFLINE_TOL_SEC) ? now - prevTick - 1 : 0;
    }

    // True when minute-of-day is in [start, end); a window that ends before it starts wraps midnight.
    function inWindow(minute as Number, start as Number, end as Number) as Boolean {
        var s = (start % DAY_MIN + DAY_MIN) % DAY_MIN;
        var e = (end % DAY_MIN + DAY_MIN) % DAY_MIN;
        return s <= e ? (minute >= s && minute < e) : (minute >= s || minute < e);
    }

    // Local civil date to days since epoch (inverse of civil).
    function daysFromCivil(y as Number, m as Number, d as Number) as Number {
        var yy = m <= 2 ? y - 1 : y;
        var era = (yy >= 0 ? yy : yy - 399) / 400;
        var yoe = yy - era * 400;
        var mp = m > 2 ? m - 3 : m + 9;
        var doy = (153 * mp + 2) / 5 + d - 1;
        var doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
        return era * 146097 + doe - 719468;
    }

    function legendOk(scrollSessions as Number, activitySessions as Number) as Boolean {
        return activitySessions > scrollSessions && activitySessions >= LEGEND_MIN_ACTIVITY;
    }

    function isDetour(durationSec as Number, gapSec as Number) as Boolean {
        return durationSec <= DETOUR_SESSION_MAX_SEC && gapSec >= 0 && gapSec <= DETOUR_WINDOW_SEC;
    }

    function milestoneId(cleanDays as Number) as Symbol? {
        var i = MILESTONE_DAYS.indexOf(cleanDays);
        return i < 0 ? null : MILESTONE_IDS[i];
    }

    // Days-since-epoch to [year, month, day] (proleptic Gregorian, no time zone involved).
    function civil(dayNum as Number) as Array<Number> {
        var z = dayNum + 719468;
        var era = z / 146097;
        var doe = z - era * 146097;
        var yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
        var doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        var mp = (5 * doy + 2) / 153;
        var day = doy - (153 * mp + 2) / 5 + 1;
        var month = mp < 10 ? mp + 3 : mp - 9;
        return [yoe + era * 400 + (month <= 2 ? 1 : 0), month, day];
    }

    // 1 = Sunday ... 7 = Saturday; day 0 (1970-01-01) was a Thursday.
    function weekdayOf(dayNum as Number) as Number {
        return (dayNum + 4) % 7 + 1;
    }

    function idToStr(id as Symbol) as String? {
        var i = IDS.indexOf(id);
        return i < 0 ? null : STRS[i];
    }

    function strToId(s as String) as Symbol? {
        var i = STRS.indexOf(s);
        return i < 0 ? null : IDS[i];
    }

    // ---- state ----

    function zeros(n as Number) as Array<Number> {
        var a = [] as Array<Number>;
        for (var i = 0; i < n; i++) {
            a.add(0);
        }
        return a;
    }

    function clear() as Void {
        _loaded = true;
        _dayKey = 0;
        _mon = 0;
        _scr = 0;
        _ovd = 0;
        _w = zeros(6);
        _fl = zeros(5);
        _lastTick = 0;
        _dwRun = 0;
        _foRun = 0;
        _gap = 0;
        _streak = 0;
        _best = 0;
        _base = 0;
        _clean = 0;
        _analog = 0;
        _sunMonth = 0;
        _sunCount = 0;
        _ring = zeros(RING_DAYS * 2);
        _hist = [];
        _mKey = [];
        _mSec = [];
        _mMon = [];
        _cnt = zeros(IDS.size());
        _lastAt = zeros(IDS.size());
        _unseen = [];
        _buzz = false;
        _detourAt = 0;
        _detourDur = 0;
    }

    function reset() as Void {
        clear();
        var s = Application.Storage;
        var keys = ["bd_day", "bd_stat", "bd_ring", "bd_hist", "bd_mon", "bd_cnt", "bd_last", "bd_new"];
        for (var i = 0; i < keys.size(); i++) {
            s.deleteValue(keys[i]);
        }
    }

    function load() as Void {
        if (_loaded) {
            return;
        }
        clear();
        var s = Application.Storage;
        var day = s.getValue("bd_day") as Array?;
        var stat = s.getValue("bd_stat") as Array?;
        var ring = s.getValue("bd_ring") as Array?;
        var cnt = s.getValue("bd_cnt") as Array?;
        var last = s.getValue("bd_last") as Array?;
        if (day == null || stat == null || ring == null || cnt == null || last == null
            || day.size() != 15 || stat.size() != 11 || ring.size() != RING_DAYS * 2
            || cnt.size() != IDS.size() || last.size() != IDS.size()) {
            return;
        }
        _dayKey = day[0] as Number;
        _mon = day[1] as Number;
        _scr = day[2] as Number;
        _ovd = day[3] as Number;
        _w = day.slice(4, 10) as Array<Number>;
        _fl = day.slice(10, 15) as Array<Number>;
        _streak = stat[0] as Number;
        _best = stat[1] as Number;
        _base = stat[2] as Number;
        _clean = stat[3] as Number;
        _analog = stat[4] as Number;
        _sunMonth = stat[5] as Number;
        _sunCount = stat[6] as Number;
        _lastTick = stat[7] as Number;
        _dwRun = stat[8] as Number;
        _foRun = stat[9] as Number;
        _gap = stat[10] as Number;
        _ring = ring as Array<Number>;
        _cnt = cnt as Array<Number>;
        _lastAt = last as Array<Number>;
        var h = s.getValue("bd_hist") as Array?;
        if (h != null) {
            _hist = h as Array<Array<Number>>;
        }
        var m = s.getValue("bd_mon") as Array?;
        if (m != null && m.size() == 3) {
            _mKey = m[0] as Array<Number>;
            _mSec = m[1] as Array<Number>;
            _mMon = m[2] as Array<Number>;
        }
        var u = s.getValue("bd_new") as Array?;
        if (u != null) {
            _unseen = u as Array<String>;
        }
        if (_dayKey != 0) {
            deriveDay();
        }
    }

    function save() as Void {
        load();
        var s = Application.Storage;
        var day = [_dayKey, _mon, _scr, _ovd] as Array<Number>;
        day.addAll(_w);
        day.addAll(_fl);
        s.setValue("bd_day", day);
        s.setValue("bd_stat", [_streak, _best, _base, _clean, _analog, _sunMonth, _sunCount,
            _lastTick, _dwRun, _foRun, _gap]);
        s.setValue("bd_ring", _ring);
        s.setValue("bd_hist", _hist);
        s.setValue("bd_mon", [_mKey, _mSec, _mMon]);
        s.setValue("bd_cnt", _cnt);
        s.setValue("bd_last", _lastAt);
        s.setValue("bd_new", _unseen);
    }

    function profileMin(d as Time.Duration?, fallback as Number) as Number {
        if (d == null) {
            return fallback;
        }
        var m = d.value() / 60;
        return (m < 0 || m > 1439) ? fallback : m;
    }

    function deriveDay() as Void {
        var c = civil(_dayKey);
        _y = c[0];
        _m = c[1];
        _d = c[2];
        _wk = weekdayOf(_dayKey);
        var wake = WAKE_DEFAULT_MIN;
        var sleep = SLEEP_DEFAULT_MIN;
        var p = UserProfile.getProfile();
        if (p != null) {
            wake = profileMin(p.wakeTime, WAKE_DEFAULT_MIN);
            sleep = profileMin(p.sleepTime, SLEEP_DEFAULT_MIN);
        }
        _wake = wake;
        _sleep = sleep;
    }

    function newDay(key as Number) as Void {
        _dayKey = key;
        _mon = 0;
        _scr = 0;
        _ovd = 0;
        var sunMon = _w[2];
        var sunScr = _w[3];
        _w = zeros(6);
        _fl = zeros(5);
        var slot = (key % RING_DAYS) * 2;
        _ring[slot] = 0;
        _ring[slot + 1] = 0;
        deriveDay();
        // A sunset window that wraps midnight is judged the next morning, so keep its evening part.
        if (_sleep < _wake) {
            _w[2] = sunMon;
            _w[3] = sunScr;
        }
    }

    function award(id as Symbol) as Void {
        load();
        var i = IDS.indexOf(id);
        if (i < 0 || (_cnt[i] > 0 && !(DEFS[i][2] as Boolean))) {
            return;
        }
        _cnt[i] += 1;
        _lastAt[i] = Time.now().value();
        var s = STRS[i];
        if (_unseen.indexOf(s) < 0) {
            _unseen.add(s);
        }
        _buzz = true;
    }

    function ringAdd(offset as Number) as Void {
        var slot = (_dayKey % RING_DAYS) * 2 + offset;
        _ring[slot] += 1;
    }

    // Folds one finished local day into streaks, history and the rolling totals.
    function closeDay(key as Number, monSec as Number, ovdSec as Number, scrSec as Number, sunset as Boolean) as Void {
        load();
        var c = civil(key);
        var clean = isCleanDay(monSec, ovdSec);
        _hist.add([clean ? 1 : 0, sunset ? 1 : 0, (scrSec + 59) / 60, monSec, weekdayOf(key), c[1], c[2]]);
        if (_hist.size() > HIST_DAYS) {
            _hist = _hist.slice(_hist.size() - HIST_DAYS, null) as Array<Array<Number>>;
        }
        var s = evalStreak(_streak, _best, _base, clean);
        _streak = s[0];
        _best = s[1];
        _base = s[2];
        if (clean) {
            _clean += 1;
            award(:firstClose);
            var ms = milestoneId(_clean);
            if (ms != null) {
                award(ms);
            }
            if (_streak % WEEK_DAYS == 0) {
                award(:perfectWeek);
            }
            if (s[3] == 1) {
                award(:longestStreak);
            }
        }
        _analog = (clean && sunset) ? _analog + 1 : 0;
        if (_analog > 0 && _analog % WEEK_DAYS == 0) {
            award(:perfectAnalogWeek);
        }
        var n = _hist.size();
        if (n >= 2 && weekendOk(_hist[n - 2], _hist[n - 1])) {
            award(:weekendOffGrid);
        }
        if (c[1] == 1 && c[2] == 1 && festiveRun(_hist)) {
            award(:festiveUnplug);
        }
        var sc = 0;
        var ac = 0;
        for (var i = 0; i < RING_DAYS; i++) {
            sc += _ring[i * 2];
            ac += _ring[i * 2 + 1];
        }
        var lastLegend = lastEarnedAt(:localLegend);
        if (legendOk(sc, ac) && (lastLegend == null || Time.now().value() - lastLegend >= LEGEND_COOLDOWN_SEC)) {
            award(:localLegend);
        }
        var nextSlot = ((key + 1) % RING_DAYS) * 2;
        _ring[nextSlot] = 0;
        _ring[nextSlot + 1] = 0;
        addMonth(c[0] * 12 + c[1] - 1, scrSec, monSec);
        if (civil(key + 1)[1] != c[1]) {
            evalMonth();
        }
    }

    function addMonth(mk as Number, scrSec as Number, monSec as Number) as Void {
        var n = _mKey.size();
        if (n > 0 && _mKey[n - 1] == mk) {
            _mSec[n - 1] += scrSec;
            _mMon[n - 1] += monSec;
            return;
        }
        _mKey.add(mk);
        _mSec.add(scrSec);
        _mMon.add(monSec);
        if (_mKey.size() > MONTHS_KEPT) {
            _mKey = _mKey.slice(1, null) as Array<Number>;
            _mSec = _mSec.slice(1, null) as Array<Number>;
            _mMon = _mMon.slice(1, null) as Array<Number>;
        }
    }

    // The newest month entry is the one that just ended.
    function evalMonth() as Void {
        var last = _mKey.size() - 1;
        if (last < 1) {
            return;
        }
        var from = last - PRIOR_MONTHS;
        if (from < 0) {
            from = 0;
        }
        var scr = 0;
        var mon = 0;
        for (var i = from; i < last; i++) {
            scr += _mSec[i];
            mon += _mMon[i];
        }
        var tier = reclaimedTier(_mSec[last].toFloat() / 3600.0, _mMon[last].toFloat() / 3600.0,
            scr.toFloat() / 3600.0, mon.toFloat() / 3600.0);
        var t = RECLAIM_HOURS.indexOf(tier);
        if (t >= 0) {
            award(RECLAIM_IDS[t]);
        }
    }

    // Local day number from the local calendar date; recomputed only when the clock minute changes.
    function keyFor(minuteOfDay as Number) as Number {
        if (minuteOfDay != _cMin || _cKey == 0) {
            var g = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
            _cKey = daysFromCivil(g.year as Number, g.month as Number, g.day as Number);
            _cMin = minuteOfDay;
        }
        return _cKey;
    }

    function dayKeyNow() as Number {
        var c = System.getClockTime();
        return keyFor(c.hour * 60 + c.min);
    }

    function syncDay(key as Number) as Void {
        if (key == _dayKey) {
            return;
        }
        if (_dayKey != 0 && key > _dayKey) {
            closeDay(_dayKey, _mon, _ovd, _scr, _fl[3] == 1);
            if (key - _dayKey >= RING_DAYS) {
                _ring = zeros(RING_DAYS * 2);
            }
            var k = _dayKey + 1;
            if (key - k > HIST_DAYS) {
                k = key - HIST_DAYS;
            }
            for (; k < key; k++) {
                closeDay(k, 0, 0, 0, false);
            }
        }
        newDay(key);
    }

    // ---- hooks ----

    function onTick(scrolling as Boolean, overdrawn as Boolean, online as Boolean) as Void {
        load();
        var now = Time.now().value();
        var c = System.getClockTime();
        var min = c.hour * 60 + c.min;
        syncDay(keyFor(min));
        if (_lastTick > 0 && now == _lastTick) {
            return;
        }
        var off = offlineGap(_lastTick, now);
        _lastTick = now;
        if (!online) {
            off += 1;
        }
        if (off > 0) {
            _dwRun = 0;
            _gap += off;
            if (_gap > FONDO_GAP_SEC) {
                _foRun = 0;
                _gap = 0;
            } else {
                _foRun += off;
            }
        }
        if (online) {
            tickMonitored(scrolling, overdrawn, min);
        }
        if (_fl[0] == 0 && min >= _wake + WINDOW_MIN) {
            _fl[0] = 1;
            if (windowClean(_w[0], _w[1], WINDOW_NEED_SEC)) {
                award(:screenFreeMorning);
            }
        }
        if (_fl[1] == 0 && min >= _sleep) {
            _fl[1] = 1;
            if (windowClean(_w[2], _w[3], WINDOW_NEED_SEC)) {
                _fl[3] = 1;
                award(:digitalSunset);
            }
            if (_sleep < _wake) {
                _w[2] = 0;
                _w[3] = 0;
            }
        }
        var uLen = SUNDAY_END_MIN - _wake;
        if (_fl[2] == 0 && _wk == SUNDAY && min >= SUNDAY_END_MIN) {
            _fl[2] = 1;
            if (uLen > 0 && windowClean(_w[4], _w[5], uLen * 60 * SUNDAY_NEED_PCT / 100)) {
                sundayDone();
            }
        }
    }

    function tickMonitored(scrolling as Boolean, overdrawn as Boolean, min as Number) as Void {
        _mon += 1;
        var s = scrolling ? 1 : 0;
        if (inWindow(min, _wake, _wake + WINDOW_MIN)) {
            _w[0] += 1;
            _w[1] += s;
        }
        if (inWindow(min, _sleep - WINDOW_MIN, _sleep)) {
            _w[2] += 1;
            _w[3] += s;
        }
        if (min >= _wake && min < SUNDAY_END_MIN) {
            _w[4] += 1;
            _w[5] += s;
        }
        if (scrolling) {
            _scr += 1;
            if (overdrawn) {
                _ovd += 1;
            }
            _dwRun = 0;
            _foRun = 0;
            _gap = 0;
            return;
        }
        _foRun += 1;
        if (inWindow(min, _wake, _sleep)) {
            _dwRun += 1;
        } else {
            _dwRun = 0;
        }
        if (_dwRun >= DEEP_WORK_SEC && _fl[4] == 0) {
            _fl[4] = 1;
            award(:deepWork100);
        }
        if (_foRun >= FONDO_SEC) {
            _foRun = 0;
            _gap = 0;
            award(:analogFondo);
        }
    }

    function sundayDone() as Void {
        var mk = _y * 12 + _m - 1;
        if (_sunMonth != mk) {
            _sunMonth = mk;
            _sunCount = 0;
        }
        _sunCount += 1;
        if (_sunCount == SUNDAYS_NEEDED) {
            award(:sundayReset);
        }
    }

    function onScrollSessionEnd(durationSec as Number) as Void {
        load();
        ringAdd(0);
        _detourAt = Time.now().value();
        _detourDur = durationSec;
    }

    function onActivityStart(kind as Symbol) as Void {
        load();
        if (_detourAt > 0 && isDetour(_detourDur, Time.now().value() - _detourAt)) {
            award(:dopamineDetour);
        }
        _detourAt = 0;
    }

    function onActivityCredited(kind as Symbol, sec as Number) as Void {
        load();
        ringAdd(1);
    }

    function takeBuzz() as Boolean {
        var b = _buzz;
        _buzz = false;
        return b;
    }

    // ---- UI ----

    function all() as Array<Dictionary> {
        var out = [] as Array<Dictionary>;
        for (var i = 0; i < IDS.size(); i++) {
            var d = DEFS[i];
            out.add({:id => IDS[i], :name => d[0], :desc => d[1], :repeatable => d[2]});
        }
        return out;
    }

    function get(id as Symbol) as Dictionary? {
        var i = IDS.indexOf(id);
        if (i < 0) {
            return null;
        }
        var d = DEFS[i];
        return {:id => id, :name => d[0], :desc => d[1], :repeatable => d[2]};
    }

    function earnedCount(id as Symbol) as Number {
        load();
        var i = IDS.indexOf(id);
        return i < 0 ? 0 : _cnt[i];
    }

    function lastEarnedAt(id as Symbol) as Number? {
        load();
        var i = IDS.indexOf(id);
        return (i < 0 || _lastAt[i] == 0) ? null : _lastAt[i];
    }

    function streak() as Number {
        load();
        return _streak;
    }

    function bestStreak() as Number {
        load();
        return _best;
    }

    function cleanDays() as Number {
        load();
        return _clean;
    }

    function pr(current as Number, target as Number, unit as String) as Dictionary {
        return {:current => current > target ? target : current, :target => target, :unit => unit};
    }

    function progress(id as Symbol) as Dictionary {
        load();
        if (id == :firstClose) {
            return pr(_clean, 1, "days");
        } else if (id == :perfectWeek) {
            return pr(_streak % WEEK_DAYS, WEEK_DAYS, "days");
        } else if (id == :longestStreak) {
            return pr(_streak, _best + 1, "days");
        } else if (id == :perfectAnalogWeek) {
            return pr(_analog % WEEK_DAYS, WEEK_DAYS, "days");
        } else if (id == :screenFreeMorning) {
            return pr(_w[1] > 0 ? 0 : _w[0] / 60, WINDOW_MIN, "min");
        } else if (id == :digitalSunset) {
            return pr(_w[3] > 0 ? 0 : _w[2] / 60, WINDOW_MIN, "min");
        } else if (id == :deepWork100) {
            return pr(_dwRun / 60, DEEP_WORK_SEC / 60, "min");
        } else if (id == :analogFondo) {
            return pr(_foRun / 3600, FONDO_SEC / 3600, "h");
        } else if (id == :sundayReset) {
            return pr(_sunMonth == _y * 12 + _m - 1 ? _sunCount : 0, SUNDAYS_NEEDED, "sundays");
        }
        var m = MILESTONE_IDS.indexOf(id);
        if (m >= 0) {
            return pr(_clean, MILESTONE_DAYS[m], "days");
        }
        var n = earnedCount(id);
        return pr(n > 0 ? 1 : 0, 1, "times");
    }

    function unseen() as Array<Symbol> {
        load();
        var out = [] as Array<Symbol>;
        for (var i = 0; i < _unseen.size(); i++) {
            var id = strToId(_unseen[i]);
            if (id != null) {
                out.add(id);
            }
        }
        return out;
    }

    function markSeen() as Void {
        load();
        _unseen = [];
    }

    // Demo only: closes today now, as if midnight passed, so a badge can be shown on stage.
    // A day under MIN_MONITORED_SEC counts as fully monitored here; the accumulators are then reset.
    function demoCloseToday() as Void {
        load();
        if (_dayKey == 0) {
            newDay(dayKeyNow());
        }
        var mon = _mon < MIN_MONITORED_SEC ? MIN_MONITORED_SEC : _mon;
        closeDay(_dayKey, mon, _ovd, _scr, _fl[3] == 1);
        newDay(_dayKey);
        _buzz = true;
    }

    // Six past clean days, with :firstClose already earned, so the next clean day closes a Perfect Week.
    function seedDemo() as Void {
        load();
        var key = dayKeyNow();
        _hist = [];
        for (var i = 6; i >= 1; i--) {
            var c = civil(key - i);
            _hist.add([1, 0, 5, MIN_MONITORED_SEC, weekdayOf(key - i), c[1], c[2]]);
        }
        _streak = 6;
        _best = 6;
        _base = 0;
        _clean = 6;
        _analog = 0;
        _cnt[0] = 1;
        _lastAt[0] = Time.now().value();
        newDay(key);
    }
}
