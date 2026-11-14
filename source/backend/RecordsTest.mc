// Why this exists: unit tests for Records, the history the trend pages read.
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

module RecordsTest {
    function same(a as Array<Number>, b as Array<Number>) as Boolean {
        if (a.size() != b.size()) {
            return false;
        }
        for (var i = 0; i < a.size(); i++) {
            if (a[i] != b[i]) {
                return false;
            }
        }
        return true;
    }

    // Records.reset() also deletes Records' own Storage key, so each test ends with it.
    (:test)
    function demoWhenFresh(logger as Logger) as Boolean {
        Records.reset();
        var ok = Records.isDemo()
            && same(Records.weekDayMin(), Records.DEMO_WEEK_DAY_MIN)
            && same(Records.weekNightMin(), Records.DEMO_WEEK_NIGHT_MIN)
            && same(Records.todayHourlyMin(), Records.DEMO_TODAY_HOURLY_MIN)
            && same(Records.lastNightBins(), Records.DEMO_LAST_NIGHT_BINS)
            && Records.lastWeekTaxed() == Records.DEMO_LAST_WEEK_TAXED;
        Records.reset();
        return ok;
    }

    (:test)
    function scrollMakesItReal(logger as Logger) as Boolean {
        Records.reset();
        for (var i = 0; i < 120; i++) {
            Records.addScrollSecond(70, 3);
        }
        var h = System.getClockTime().hour;
        var ok = !Records.isDemo() && Records.todayHourlyMin()[h] == 2;
        Records.reset();
        return ok;
    }

    (:test)
    function earnedShowsInHourly(logger as Logger) as Boolean {
        Records.reset();
        Records.addEarned(600);
        var h = System.getClockTime().hour;
        var ok = !Records.isDemo() && Records.todayEarnedHourly()[h] == 10 && Records.weekEarnedMin()[6] == 10;
        Records.reset();
        return ok;
    }

    (:test)
    function formatsMinutes(logger as Logger) as Boolean {
        return Records.fmtMin(38).equals("38 min") && Records.fmtMin(125).equals("2h 05m");
    }

    (:test)
    function taxedUsesNightRate(logger as Logger) as Boolean {
        Records.reset();
        var ok = Records.taxedOn(0) == Records.DEMO_WEEK_DAY_MIN[0] + Records.DEMO_WEEK_NIGHT_MIN[0] * Records.NIGHT_RATE;
        Records.reset();
        return ok;
    }

    (:test)
    function taxedIsWhatWasCharged(logger as Logger) as Boolean {
        Records.reset();
        for (var i = 0; i < 120; i++) {
            Records.addScrollSecond(70, 3);
        }
        var ok = Records.taxedOn(6) == 6 && Records.weekTaxed() == 6 && Records.todayTaxed() == 6;
        Records.reset();
        return ok;
    }

    (:test)
    function persistenceSurvivesLoad(logger as Logger) as Boolean {
        Records.reset();
        for (var i = 0; i < 120; i++) {
            Records.addScrollSecond(70, 3);
        }
        Records.save();
        Records.unload();
        Records.load();
        var h = System.getClockTime().hour;
        var ok = !Records.isDemo() && Records.todayHourlyMin()[h] == 2 && Records.taxedOn(6) == 6;
        Records.reset();
        return ok;
    }

    (:test)
    function seedFillsPreviousDays(logger as Logger) as Boolean {
        Records.reset();
        Records.seedDemoHistory();
        var d = Records.weekDayMin();
        var n = Records.weekNightMin();
        var e = Records.weekEarnedMin();
        var ok = !Records.isDemo() && Records.weekSpo2()[5] == Records.DEMO_WEEK_SPO2[5];
        for (var i = 0; i < 6; i++) {
            ok = ok && d[i] == Records.DEMO_WEEK_DAY_MIN[i] && n[i] == Records.DEMO_WEEK_NIGHT_MIN[i]
                && e[i] == Records.DEMO_WEEK_EARNED_MIN[i]
                && Records.taxedOn(i) == Records.DEMO_WEEK_DAY_MIN[i] + Records.DEMO_WEEK_NIGHT_MIN[i] * Records.NIGHT_RATE;
        }
        ok = ok && same(Records.lastNightBins(), Records.DEMO_LAST_NIGHT_BINS);
        Records.reset();
        return ok;
    }

    (:test)
    function seedRunsOnce(logger as Logger) as Boolean {
        Records.reset();
        Records.seedDemoHistory();
        var before = Records.weekTaxed();
        var hourly = Records.sum(Records.todayHourlyMin());
        var sessions = Records.todaySessions().size();
        Records.seedDemoHistory();
        var ok = Records.weekTaxed() == before && Records.sum(Records.todayHourlyMin()) == hourly
            && Records.todaySessions().size() == sessions;
        Records.reset();
        return ok;
    }

    (:test)
    function seedKeepsRealData(logger as Logger) as Boolean {
        Records.reset();
        for (var i = 0; i < 120; i++) {
            Records.addScrollSecond(70, 3);
        }
        Records.seedDemoHistory();
        var h = System.getClockTime().hour;
        var ok = Records.todayHourlyMin()[h] == 2 && Records.taxedOn(6) >= 6;
        Records.reset();
        return ok;
    }

    (:test)
    function seedSurvivesReload(logger as Logger) as Boolean {
        Records.reset();
        Records.seedDemoHistory();
        var before = Records.weekTaxed();
        Records.save();
        Records.unload();
        Records.load();
        var ok = Records._seeded;
        Records.seedDemoHistory();
        ok = ok && Records.weekTaxed() == before && !Records.isDemo();
        Records.reset();
        return ok;
    }

    (:test)
    function seededWeekTaxedAddsUp(logger as Logger) as Boolean {
        Records.reset();
        Records.seedDemoHistory();
        var t = Records.todayTaxed();
        for (var i = 0; i < 6; i++) {
            t += Records.taxedOn(i);
        }
        var ok = Records.weekTaxed() == t;
        Records.reset();
        return ok;
    }

    (:test)
    function resetClearsSeed(logger as Logger) as Boolean {
        Records.reset();
        Records.seedDemoHistory();
        Records.save();
        Records.reset();
        Records.unload();
        Records.load();
        var ok = !Records._seeded && Records.isDemo();
        Records.reset();
        return ok;
    }
}
