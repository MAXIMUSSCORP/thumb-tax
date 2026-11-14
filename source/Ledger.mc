// Thumb Tax's own records: minutes scrolled, taxed and earned back. These are not Garmin's built-in metrics.
// The detector does not write sessions yet, so every series here is demo data (DEMO = true) for building the UI.
// Swap these constants for stored records once detection exists; the trend pages only read through this module.
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

module Ledger {
    const DEMO = true;

    // Night scrolling costs double.
    const NIGHT_RATE = 2;

    // Week series: oldest first, last entry is today.
    const WEEK_DAY_MIN = [22, 35, 18, 40, 28, 15, 12] as Array<Number>;
    // Minutes scrolled during the night that ended on that morning.
    const WEEK_NIGHT_MIN = [45, 30, 55, 20, 60, 25, 38] as Array<Number>;
    const WEEK_EARNED_MIN = [10, 15, 0, 20, 5, 30, 15] as Array<Number>;
    // Heart rate while scrolling at night, above the wind-down rate (bpm).
    const WEEK_HR_LIFT = [9, 6, 11, 4, 12, 5, 8] as Array<Number>;
    // Overnight average SpO2 (%).
    const WEEK_SPO2 = [94, 96, 93, 97, 93, 96, 95] as Array<Number>;
    const LAST_WEEK_TAXED = 520;
    // A night counts as a "scroll night" above this many minutes.
    const SCROLL_NIGHT_MIN = 30;

    // Today, by hour (0 = midnight).
    const TODAY_HOURLY_MIN = [12, 8, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 5, 2, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0] as Array<Number>;
    const TODAY_EARNED_HOURLY = [0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 0, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0] as Array<Number>;
    // Last night, hourly from 20:00 to 08:00.
    const LAST_NIGHT_BINS = [0, 0, 10, 8, 12, 8, 0, 0, 0, 0, 0, 0] as Array<Number>;
    const LAST_NIGHT_START_HOUR = 20;
    // Today's scroll sessions as [start, end] minutes since midnight.
    const TODAY_SESSIONS = [[0, 12], [60, 68], [480, 483], [720, 725], [780, 782], [1020, 1022]] as Array<Array<Number>>;

    function isNightHour(h as Number) as Boolean {
        return h >= 22 || h < 6;
    }

    function taxedOn(i as Number) as Number {
        return WEEK_DAY_MIN[i] + WEEK_NIGHT_MIN[i] * NIGHT_RATE;
    }

    function weekTaxed() as Number {
        var t = 0;
        for (var i = 0; i < WEEK_DAY_MIN.size(); i++) {
            t += taxedOn(i);
        }
        return t;
    }

    function todayTaxed() as Number {
        var t = 0;
        for (var h = 0; h < 24; h++) {
            t += TODAY_HOURLY_MIN[h] * (isNightHour(h) ? NIGHT_RATE : 1);
        }
        return t;
    }

    function inSession(minute as Number) as Boolean {
        for (var i = 0; i < TODAY_SESSIONS.size(); i++) {
            var s = TODAY_SESSIONS[i];
            if (minute >= s[0] && minute <= s[1]) {
                return true;
            }
        }
        return false;
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
