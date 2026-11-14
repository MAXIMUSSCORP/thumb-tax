// Unit tests for Sync's pure functions (usage deltas, suggestion wording, payload); no network.
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Test;

module SyncTest {
    function delta(sd as String?, s as Number, d as String, u as Number, tax as Number, ns as Number) as Void {
        epochDelta(sd, s, null, d, u, null, tax, ns);
    }

    function epochDelta(sd as String?, s as Number, se as String?, d as String, u as Number, e as String?, tax as Number, ns as Number) as Void {
        var r = Sync.usageDelta(sd, s, se, d, u, e);
        Test.assertEqual(r[0], tax);
        Test.assertEqual(r[1], ns);
    }

    (:test)
    function usageEpochCases(logger as Logger) as Boolean {
        epochDelta("d", 40, "a", "d", 3, "b", 0, 3);
        epochDelta("d", 3, "b", "d", 7, "b", 4, 7);
        epochDelta("d", 40, "b", "d", 3, "b", 0, 40);
        epochDelta("d", 40, null, "d", 3, "b", 0, 40);
        epochDelta("d", 40, "a", "d", 3, null, 0, 40);
        epochDelta("d", 40, "a", "d", 43, null, 3, 43);
        epochDelta(null, 0, "a", "d", 50, "b", 0, 50);
        epochDelta("d1", 200, "a", "d2", 4, "a", 4, 4);
        epochDelta("d1", 200, "a", "d2", 4, "b", 0, 4);
        return true;
    }

    (:test)
    function usageDeltaCases(logger as Logger) as Boolean {
        delta(null, 0, "d", 50, 0, 50);
        delta("d", 50, "d", 53, 3, 53);
        delta("d", 50, "d", 80, 30, 80);
        delta("d", 0, "d", 500, 120, 500);
        delta("d", 50, "d", 50, 0, 50);
        delta("d", 50, "d", 2, 0, 50);
        delta("d", 50, "d", 53, 3, 53);
        delta("d1", 200, "d2", 4, 4, 4);
        return true;
    }

    (:test)
    function statusTextCases(logger as Logger) as Boolean {
        Test.assertEqual(Sync.statusTextFor(-1001, false), "SYNC -1001 HTTPS");
        Test.assertEqual(Sync.statusTextFor(401, true), "SYNC 401 KEY");
        Test.assertEqual(Sync.statusTextFor(409, true), "SYNC 409");
        Test.assertEqual(Sync.statusTextFor(200, true), "");
        Test.assertEqual(Sync.statusTextFor(-408, false), "SYNC OFFLINE");
        return true;
    }

    // Credit per minute: jumping jacks 180 s, stairs 480 s, high knees/plank 180 s, cold shower 240 s, walk 60 s.
    // Rep kinds over 50 reps and stairs over 15 floors are skipped as impractical.
    (:test)
    function suggestionText(logger as Logger) as Boolean {
        Test.assertEqual(Sync.suggestion(0), "Earn 10 min to scroll: 5 floors of stairs");
        Test.assertEqual(Sync.suggestion(60), "20 jumping jacks or 10 squats clears it. +10 min to scroll: 5 floors of stairs");
        Test.assertEqual(Sync.suggestion(120), "40 jumping jacks or 20 squats clears it. +10 min to scroll: 5 floors of stairs");
        Test.assertEqual(Sync.suggestion(600), "5 floors of stairs or 3 min cold shower clears it. +10 min to scroll: 5 floors of stairs");
        Test.assertEqual(Sync.suggestion(2400), "14 min high knees or 14 min plank clears it. +10 min to scroll: 5 floors of stairs");
        Test.assertEqual(Sync.suggestion(7200), "40 min high knees or 40 min plank clears it. +10 min to scroll: 5 floors of stairs");
        return true;
    }

    (:test)
    function suggestionFilters(logger as Logger) as Boolean {
        var long = Sync.suggestion(2400);
        Test.assert(long.find("50 min walk") == null);
        Test.assert(long.find("cold shower") == null);
        var debts = [60, 600, 720, 721, 2400, 7200];
        for (var i = 0; i < debts.size(); i++) {
            var s = Sync.suggestion(debts[i] as Number);
            Test.assert(s.length() <= 120);
            Test.assert(s.find("sunlight") == null);
            Test.assert(s.find("mow") == null);
            Test.assert(s.find("meditation") == null);
            Test.assert(s.find("!") == null);
        }
        Test.assert(Sync.suggestion(720).find("cold shower") != null);
        Test.assert(Sync.suggestion(721).find("cold shower") == null);
        return true;
    }

    // Walk credit is 80 m/min * 750 s/km = 60 s per minute.
    (:test)
    function walkOption(logger as Logger) as Boolean {
        var o = Sync.option(:walk, 2400, true) as Dictionary;
        Test.assertEqual(o[:min], 40);
        Test.assertEqual(o[:text], "a 40 min walk");
        Test.assert(Sync.option(:nope, 60, true) == null);
        return true;
    }

    (:test)
    function payloadCases(logger as Logger) as Boolean {
        var a = Sync.payload(-61, 0, 1);
        Test.assertEqual(a["taxMinutes"], 2);
        Test.assertEqual(a["creditMinutes"], 0);
        Test.assertEqual(a["source"], "watch");
        var b = Sync.payload(125, 0, 1);
        Test.assertEqual(b["taxMinutes"], 0);
        Test.assertEqual(b["creditMinutes"], 2);
        Test.assertEqual(b["activity"], "Earn 10 min to scroll: 5 floors of stairs");
        Test.assertEqual(a["activity"], Sync.suggestion(61));
        Test.assertEqual(Sync.payload(60, 60, 2)["taxMinutes"], 1);
        return true;
    }

    (:test)
    function headersCases(logger as Logger) as Boolean {
        var a = Sync.headersFor("");
        Test.assertEqual(a["ngrok-skip-browser-warning"], "1");
        Test.assertEqual(a["Content-Type"], Communications.REQUEST_CONTENT_TYPE_JSON);
        Test.assert(!a.hasKey("x-api-key"));
        var b = Sync.headersFor("k");
        Test.assertEqual(b["x-api-key"], "k");
        Test.assertEqual(b["ngrok-skip-browser-warning"], "1");
        return true;
    }

    (:test)
    function pollDueCases(logger as Logger) as Boolean {
        Test.assert(Sync.pollDue(null, 5));
        Test.assert(!Sync.pollDue(1000, 1000 + POLL_MS - 1));
        Test.assert(Sync.pollDue(1000, 1000 + POLL_MS));
        Test.assert(Sync.pollDue(9000, 100));
        return true;
    }
}
