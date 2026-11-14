// Unit tests for the Badges rules; run with the simulator's unit-test mode.
import Toybox.Lang;
import Toybox.Test;

module BadgesTest {
    const BASE = 20000;

    function cleanRun(from as Number, n as Number) as Void {
        for (var i = 0; i < n; i++) {
            Badges.closeDay(from + i, 7200, 0, 600, false);
        }
    }

    (:test)
    function cleanDayRule(logger as Logger) as Boolean {
        Badges.reset();
        Test.assert(Badges.isCleanDay(3600, 0));
        Test.assert(!Badges.isCleanDay(3599, 0));
        Test.assert(!Badges.isCleanDay(7200, 1));
        Badges.reset();
        return true;
    }

    (:test)
    function firstCloseOnce(logger as Logger) as Boolean {
        Badges.reset();
        cleanRun(BASE, 2);
        Test.assertEqual(Badges.earnedCount(:firstClose), 1);
        Test.assertEqual(Badges.cleanDays(), 2);
        Badges.reset();
        return true;
    }

    (:test)
    function perfectWeekAndProgress(logger as Logger) as Boolean {
        Badges.reset();
        cleanRun(BASE, 4);
        Test.assertEqual(Badges.progress(:perfectWeek)[:current], 4);
        Test.assertEqual(Badges.progress(:perfectWeek)[:target], 7);
        cleanRun(BASE + 4, 3);
        Test.assertEqual(Badges.earnedCount(:perfectWeek), 1);
        Test.assertEqual(Badges.progress(:perfectWeek)[:current], 0);
        Badges.reset();
        return true;
    }

    (:test)
    function longestStreakAfterBreak(logger as Logger) as Boolean {
        Badges.reset();
        cleanRun(BASE, 3);
        Badges.closeDay(BASE + 3, 0, 0, 0, false);
        Test.assertEqual(Badges.streak(), 0);
        cleanRun(BASE + 4, 3);
        Test.assertEqual(Badges.earnedCount(:longestStreak), 0);
        cleanRun(BASE + 7, 1);
        Test.assertEqual(Badges.earnedCount(:longestStreak), 1);
        Test.assertEqual(Badges.bestStreak(), 4);
        Badges.reset();
        return true;
    }

    (:test)
    function milestoneAt100(logger as Logger) as Boolean {
        Badges.reset();
        Badges._clean = 99;
        Test.assertEqual(Badges.earnedCount(:days100), 0);
        cleanRun(BASE, 1);
        Test.assertEqual(Badges.earnedCount(:days100), 1);
        cleanRun(BASE + 1, 1);
        Test.assertEqual(Badges.earnedCount(:days100), 1);
        Badges.reset();
        return true;
    }

    (:test)
    function dopamineDetour(logger as Logger) as Boolean {
        Badges.reset();
        Badges.onScrollSessionEnd(8);
        Badges.onActivityStart(:walkM);
        Test.assertEqual(Badges.earnedCount(:dopamineDetour), 1);
        Badges.onScrollSessionEnd(15);
        Badges.onActivityStart(:walkM);
        Test.assertEqual(Badges.earnedCount(:dopamineDetour), 1);
        Badges.reset();
        return true;
    }

    // reclaimedTier(prevScrolledH, prevMonitoredH, priorScrolledH, priorMonitoredH)
    (:test)
    function reclaimedTiers(logger as Logger) as Boolean {
        Test.assertEqual(Badges.reclaimedTier(40.0, 720.0, 60.0, 720.0), 10);
        Test.assertEqual(Badges.reclaimedTier(30.0, 720.0, 60.0, 720.0), 25);
        Test.assertEqual(Badges.reclaimedTier(5.0, 720.0, 60.0, 720.0), 50);
        Test.assertEqual(Badges.reclaimedTier(55.0, 720.0, 60.0, 720.0), 0);
        return true;
    }

    (:test)
    function reclaimedIgnoresLowMonitoring(logger as Logger) as Boolean {
        // Half the scrolling over half the monitoring is the same rate: nothing saved.
        Test.assertEqual(Badges.reclaimedTier(30.0, 360.0, 60.0, 720.0), 0);
        // Under 20 monitored hours in the month: never awarded.
        Test.assertEqual(Badges.reclaimedTier(0.0, 10.0, 100.0, 720.0), 0);
        return true;
    }

    (:test)
    function monthEvalUsesRate(logger as Logger) as Boolean {
        Badges.reset();
        for (var i = 0; i < 3; i++) {
            Badges.addMonth(24000 + i, 60 * 3600, 720 * 3600);
        }
        Badges.addMonth(24003, 30 * 3600, 360 * 3600);
        Badges.evalMonth();
        Test.assertEqual(Badges.earnedCount(:reclaimed10h) + Badges.earnedCount(:reclaimed25h)
            + Badges.earnedCount(:reclaimed50h), 0);
        Badges.addMonth(24004, 5 * 3600, 720 * 3600);
        Badges.evalMonth();
        Test.assertEqual(Badges.earnedCount(:reclaimed50h), 1);
        Badges.reset();
        return true;
    }

    (:test)
    function offlineGapTolerance(logger as Logger) as Boolean {
        Test.assertEqual(Badges.offlineGap(0, 100), 0);
        Test.assertEqual(Badges.offlineGap(100, 101), 0);
        Test.assertEqual(Badges.offlineGap(100, 102), 0);
        Test.assertEqual(Badges.offlineGap(100, 103), 0);
        Test.assertEqual(Badges.offlineGap(100, 104), 3);
        Test.assertEqual(Badges.offlineGap(100, 200), 99);
        return true;
    }

    (:test)
    function windowsWrapMidnight(logger as Logger) as Boolean {
        // Sleep 00:30: sunset window is 23:30 to 00:30.
        var start = 30 - Badges.WINDOW_MIN;
        Test.assert(Badges.inWindow(23 * 60 + 45, start, 30));
        Test.assert(Badges.inWindow(15, start, 30));
        Test.assert(!Badges.inWindow(45, start, 30));
        // Awake from 07:30 to 00:30.
        Test.assert(Badges.inWindow(23 * 60, 450, 30));
        Test.assert(!Badges.inWindow(180, 450, 30));
        Test.assert(Badges.inWindow(450, 450, 30));
        // No wrap.
        Test.assert(Badges.inWindow(600, 450, 1380));
        Test.assert(!Badges.inWindow(1380, 450, 1380));
        return true;
    }

    (:test)
    function daysFromCivilRoundTrip(logger as Logger) as Boolean {
        Test.assertEqual(Badges.daysFromCivil(1970, 1, 1), 0);
        Test.assertEqual(Badges.daysFromCivil(1970, 1, 2), 1);
        var ys = [2024, 2026, 2000] as Array<Number>;
        var ms = [2, 11, 12] as Array<Number>;
        var ds = [29, 14, 31] as Array<Number>;
        for (var i = 0; i < ys.size(); i++) {
            var c = Badges.civil(Badges.daysFromCivil(ys[i], ms[i], ds[i]));
            Test.assertEqual(c[0], ys[i]);
            Test.assertEqual(c[1], ms[i]);
            Test.assertEqual(c[2], ds[i]);
        }
        return true;
    }

    (:test)
    function longGapClearsWholeRing(logger as Logger) as Boolean {
        Badges.reset();
        Badges._dayKey = BASE;
        Badges.ringAdd(0);
        Badges.ringAdd(1);
        Badges.syncDay(BASE + 40);
        var total = 0;
        for (var i = 0; i < Badges._ring.size(); i++) {
            total += Badges._ring[i];
        }
        Test.assertEqual(total, 0);
        Badges.reset();
        return true;
    }

    (:test)
    function festiveWindowEdges(logger as Logger) as Boolean {
        Test.assert(!Badges.isFestiveDay(12, 23));
        Test.assert(Badges.isFestiveDay(12, 24));
        Test.assert(Badges.isFestiveDay(1, 1));
        Test.assert(!Badges.isFestiveDay(1, 2));
        return true;
    }

    (:test)
    function seedDemoThenPerfectWeek(logger as Logger) as Boolean {
        Badges.reset();
        Badges.seedDemo();
        Test.assertEqual(Badges.streak(), 6);
        Test.assertEqual(Badges.cleanDays(), 6);
        Test.assertEqual(Badges.unseen().size(), 0);
        Badges.closeDay(Badges.dayKeyNow(), 7200, 0, 0, false);
        Test.assert(Badges.unseen().indexOf(:perfectWeek) >= 0);
        Test.assertEqual(Badges.earnedCount(:firstClose), 1);
        Badges.reset();
        return true;
    }

    (:test)
    function demoCloseEarnsPerfectWeek(logger as Logger) as Boolean {
        Badges.reset();
        Badges.seedDemo();
        Badges.demoCloseToday();
        Test.assert(Badges.unseen().indexOf(:perfectWeek) >= 0);
        Test.assertEqual(Badges.streak(), 7);
        Badges.reset();
        return true;
    }

    (:test)
    function buzzOnce(logger as Logger) as Boolean {
        Badges.reset();
        cleanRun(BASE, 1);
        Test.assert(Badges.takeBuzz());
        Test.assert(!Badges.takeBuzz());
        Test.assert(Badges.unseen().size() > 0);
        Badges.markSeen();
        Test.assertEqual(Badges.unseen().size(), 0);
        Badges.reset();
        return true;
    }

    (:test)
    function idsRoundTrip(logger as Logger) as Boolean {
        for (var i = 0; i < Badges.IDS.size(); i++) {
            var s = Badges.idToStr(Badges.IDS[i]);
            Test.assert(s != null);
            Test.assertEqual(Badges.strToId(s as String), Badges.IDS[i]);
        }
        Test.assertEqual(Badges.all().size(), Badges.IDS.size());
        return true;
    }
}
