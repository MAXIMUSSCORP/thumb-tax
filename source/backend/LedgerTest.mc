// Unit tests for Ledger arithmetic and exchange rates; run with the simulator's unit-test mode.
import Toybox.Lang;
import Toybox.Test;
import Toybox.Application;

module LedgerTest {
    // earn() saves, so every test wipes the Ledger's own keys before returning.
    function cleanup() as Void {
        Application.Storage.deleteValue("lg_bal");
        Application.Storage.deleteValue("lg_hist");
        Application.Storage.deleteValue("lg_day");
        Ledger.reset();
    }

    (:test)
    function multiplierBoundaries(logger as Logger) as Boolean {
        Ledger.reset();
        Test.assertEqual(Ledger.multiplier(21, false), 1);
        Test.assertEqual(Ledger.multiplier(22, false), 2);
        Test.assertEqual(Ledger.multiplier(5, false), 2);
        Test.assertEqual(Ledger.multiplier(6, false), 1);
        Test.assertEqual(Ledger.multiplier(12, true), 1);
        Test.assertEqual(Ledger.multiplier(23, true), 3);
        Test.assertEqual(Ledger.multiplier(0, true), 3);
        Test.assertEqual(Ledger.multiplier(5, true), 3);
        Test.assertEqual(Ledger.multiplier(21, true), 1);
        cleanup();
        return true;
    }

    (:test)
    function chargeDayVsNight(logger as Logger) as Boolean {
        Ledger.reset();
        Test.assertEqual(Ledger.chargeScroll(10, 12, false), 10);
        Test.assertEqual(Ledger.chargeScroll(10, 23, false), 20);
        Test.assertEqual(Ledger.chargeScroll(10, 23, true), 30);
        Test.assertEqual(Ledger.balance(), -60);
        var s = Ledger.stats();
        Test.assertEqual(s[:scrollDaySec], 10);
        Test.assertEqual(s[:scrollNightSec], 20);
        Test.assertEqual(s[:feeSec], 30);
        cleanup();
        return true;
    }

    (:test)
    function creditThenDebt(logger as Logger) as Boolean {
        Ledger.reset();
        Ledger.earn(:pushups, 30);
        Test.assertEqual(Ledger.balance(), 300);
        Test.assert(!Ledger.isOverdrawn());
        Ledger.chargeScroll(200, 12, false);
        Test.assertEqual(Ledger.balance(), 100);
        Test.assert(!Ledger.isOverdrawn());
        Ledger.chargeScroll(100, 12, false);
        Test.assertEqual(Ledger.balance(), 0);
        Test.assert(!Ledger.isOverdrawn());
        Ledger.chargeScroll(1, 12, false);
        Test.assertEqual(Ledger.balance(), -1);
        Test.assert(Ledger.isOverdrawn());
        cleanup();
        return true;
    }

    (:test)
    function earnRates(logger as Logger) as Boolean {
        Ledger.reset();
        Test.assertEqual(Ledger.earn(:pushups, 12), 120);
        Test.assertEqual(Ledger.earn(:stairs, 3), 360);
        Test.assertEqual(Ledger.earn(:walkM, 1500), 1125);
        Test.assertEqual(Ledger.earn(:climbM, 50), 600);
        Test.assertEqual(Ledger.earn(:read, 1200), 600);
        Test.assertEqual(Ledger.balance(), 2805);
        Test.assertEqual(Ledger.history().size(), 5);
        Test.assertEqual(Ledger.stats()[:earnedSec], 2805);
        cleanup();
        return true;
    }

    (:test)
    function earnUnknownKind(logger as Logger) as Boolean {
        Ledger.reset();
        Test.assertEqual(Ledger.earn(:bogus, 99), 0);
        Test.assertEqual(Ledger.balance(), 0);
        Test.assertEqual(Ledger.history().size(), 0);
        cleanup();
        return true;
    }

    (:test)
    function historyCapAndSession(logger as Logger) as Boolean {
        Ledger.reset();
        for (var i = 0; i < 25; i++) {
            Ledger.earn(:pushups, 1);
        }
        Test.assertEqual(Ledger.history().size(), 20);
        Ledger.closeScrollSession(60, 120, true);
        var h = Ledger.history();
        var last = h[h.size() - 1] as Dictionary;
        Test.assertEqual(last[:delta], -120);
        Test.assertEqual(last[:reason], "night scroll");
        cleanup();
        return true;
    }

    (:test)
    function resetZeroes(logger as Logger) as Boolean {
        Ledger.reset();
        Ledger.earn(:stairs, 2);
        Ledger.chargeScroll(5, 23, true);
        Ledger.reset();
        Test.assertEqual(Ledger.balance(), 0);
        Test.assertEqual(Ledger.history().size(), 0);
        Test.assertEqual(Ledger.stats()[:feeSec], 0);
        Test.assertEqual(Ledger.stats()[:entries], 0);
        cleanup();
        return true;
    }

    (:test)
    function dailyOnce(logger as Logger) as Boolean {
        Ledger.reset();
        Test.assertEqual(Ledger.earn(:sunlight, 300), 300);
        Test.assert(Ledger.claimedToday(:sunlight));
        Test.assertEqual(Ledger.earn(:sunlight, 300), 0);
        Test.assert(!Ledger.claimedToday(:read));
        Test.assertEqual(Ledger.balance(), 300);
        cleanup();
        return true;
    }

    (:test)
    function capApplied(logger as Logger) as Boolean {
        Ledger.reset();
        Test.assertEqual(Ledger.earn(:coldShower, 300), 720);
        Test.assertEqual(Ledger.earn(:sunlight, 1200), 600);
        cleanup();
        return true;
    }

    (:test)
    function bonusAdds(logger as Logger) as Boolean {
        Ledger.reset();
        Test.assertEqual(Ledger.bonus(120, "calm bonus"), 120);
        Test.assertEqual(Ledger.bonus(0, "none"), 0);
        Test.assertEqual(Ledger.balance(), 120);
        Test.assertEqual(Ledger.history().size(), 1);
        cleanup();
        return true;
    }

    (:test)
    function unknownKindZero(logger as Logger) as Boolean {
        Ledger.reset();
        Test.assertEqual(Ledger.earn(:nope, 50), 0);
        Test.assertEqual(Ledger.earn(:pushups, 0), 0);
        Test.assertEqual(Ledger.history().size(), 0);
        cleanup();
        return true;
    }

    (:test)
    function catalogIntegrity(logger as Logger) as Boolean {
        var dets = [:reps, :tilt, :hold, :cadence, :calm, :active, :vigorous, :cold, :outdoors, :floors, :walk];
        var keys = [:id, :label, :group, :detector, :unit, :rate, :verify, :cap, :minSec, :daily, :params];
        var all = Catalog.all();
        Test.assertEqual(all.size(), Catalog.ids().size());
        for (var i = 0; i < all.size(); i++) {
            var d = all[i];
            for (var k = 0; k < keys.size(); k++) {
                Test.assert(d.hasKey(keys[k]));
            }
            Test.assert((d[:rate] as Float) >= 0.0);
            Test.assert(dets.indexOf(d[:detector]) >= 0);
            Test.assert(Catalog.get(d[:id] as Symbol) == d);
            for (var j = 0; j < i; j++) {
                Test.assert(all[j][:id] != d[:id]);
            }
        }
        return true;
    }
}
