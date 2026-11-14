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

    // Walk earns 48 s/min (80 m/min * 600 s/km), push-ups 10 s each, stairs 120 s per floor.
    (:test)
    function suggestionText(logger as Logger) as Boolean {
        Test.assertEqual(Sync.suggestion(0), "");
        Test.assertEqual(Sync.suggestion(120), "12 push-ups or a 3 min walk clears it");
        Test.assertEqual(Sync.suggestion(900), "8 floors of stairs or a 19 min walk clears it");
        Test.assertEqual(Sync.suggestion(3600), "A 75 min walk clears it");
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
        Test.assertEqual(b["activity"], "");
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
}
