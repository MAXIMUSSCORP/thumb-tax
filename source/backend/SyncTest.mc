// Unit tests for Sync's pure functions (usage deltas, suggestion wording, payload); no network.
import Toybox.Application;
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
        Test.assertEqual(a["pendingChargeSec"], 0);
        Test.assertEqual(a["activity"], Sync.suggestion(61));
        Test.assert(!a.hasKey("taxMinutes"));
        var b = Sync.payload(125, 0, 1);
        Test.assertEqual(b["activity"], "Earn 10 min to scroll: 5 floors of stairs");
        var c = Sync.payload(60, 60, 2);
        Test.assertEqual(c["pendingChargeSec"], 120);
        Test.assertEqual(c["activity"], Sync.suggestion(60));
        return true;
    }

    (:test)
    function reconcileCases(logger as Logger) as Boolean {
        Test.assertEqual(Sync.reconcile(100, 0, 0), 100);
        Test.assertEqual(Sync.reconcile(100, -8, -2), 90);
        Test.assertEqual(Sync.reconcile(-50, 0, 30), -20);
        return true;
    }

    (:test)
    function outboxAccumulatesIntoOneEvent(logger as Logger) as Boolean {
        Sync.resetOutbox();
        Sync.noteDelta(-5, "scroll");
        Sync.noteDelta(-3, "scroll");
        Sync.noteDelta(0, "ignored");
        Sync.startEvent();
        var ev = Sync._inflight as Dictionary;
        Test.assertEqual(ev[:id], 1);
        Test.assertEqual(ev[:delta], -8);
        Test.assertEqual(ev[:reason], "scroll");
        Test.assertEqual(Sync._unsent, 0);
        Sync.noteDelta(60, "Squats x6");
        Sync.startEvent();
        Test.assertEqual((Sync._inflight as Dictionary)[:id], 1);
        Test.assertEqual(Sync._unsent, 60);
        Sync.resetOutbox();
        Sync.noteDelta(-1, "scroll");
        Sync.noteDelta(10, "Squats x1");
        Test.assertEqual(Sync._unsentReason, "watch activity");
        Sync.resetOutbox();
        return true;
    }

    (:test)
    function outboxRetryAndAck(logger as Logger) as Boolean {
        Sync.resetOutbox();
        Sync.noteDelta(-8, "scroll");
        Sync.startEvent();
        Sync.noteDelta(-2, "scroll");
        Sync.startEvent();
        var ev = Sync._inflight as Dictionary;
        Test.assertEqual(ev[:id], 1);
        Test.assertEqual(ev[:delta], -8);
        Sync.ackEvent();
        Test.assert(Sync._inflight == null);
        Test.assertEqual(Sync._unsent, -2);
        Sync.startEvent();
        ev = Sync._inflight as Dictionary;
        Test.assertEqual(ev[:id], 2);
        Test.assertEqual(ev[:delta], -2);
        Sync.ackEvent();
        Sync.resetOutbox();
        Application.Storage.deleteValue(SYNC_KEY);
        return true;
    }

    (:test)
    function sessionPersisted(logger as Logger) as Boolean {
        Sync.resetOutbox();
        var s = Sync.ensureSession();
        Test.assert(s.length() > 0);
        Test.assertEqual(Sync.ensureSession(), s);
        Sync.noteDelta(-4, "scroll");
        Sync.startEvent();
        var saved = Application.Storage.getValue(SYNC_KEY);
        Sync.resetOutbox();
        Sync.restore(saved);
        Test.assertEqual(Sync.ensureSession(), s);
        Test.assertEqual(Sync._nextEventId, 2);
        Test.assertEqual((Sync._inflight as Dictionary)[:delta], -4);
        Sync.resetOutbox();
        Sync.restore(["d", 5, 7, "e"]);
        Test.assertEqual(Sync._pendingSec, 7);
        Test.assertEqual(Sync._nextEventId, 1);
        Sync.resetOutbox();
        Application.Storage.deleteValue(SYNC_KEY);
        return true;
    }

    (:test)
    function eventBodyFields(logger as Logger) as Boolean {
        Sync.resetOutbox();
        var b = Sync.eventBody({:id => 3, :delta => -9, :reason => "scroll"}, 120, "Walk");
        var keys = ["deltaSec", "reason", "source", "session", "eventId", "activity", "pendingChargeSec"];
        for (var i = 0; i < keys.size(); i++) {
            Test.assert(b.hasKey(keys[i]));
            Test.assert(b[keys[i]] != null);
        }
        Test.assertEqual(b["deltaSec"], -9);
        Test.assertEqual(b["eventId"], 3);
        Test.assertEqual(b["pendingChargeSec"], 120);
        Test.assertEqual(b["source"], "watch");
        Test.assertEqual(b["session"], Sync.ensureSession());
        var long = Sync.eventBody({:id => 1, :delta => 1, :reason => "0123456789012345678901234567890123456789012345678901234567890123"}, 0, "");
        Test.assertEqual((long["reason"] as String).length(), 60);
        Sync.resetOutbox();
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

    (:test)
    function badgeToAwardCases(logger as Logger) as Boolean {
        var c = {"seq" => 5, "id" => "pw"};
        var r = Sync.badgeToAward(3, false, null);
        Test.assert(r[0] == null);
        Test.assertEqual(r[1], 3);
        r = Sync.badgeToAward(0, true, c);
        Test.assert(r[0] == null);
        Test.assertEqual(r[1], 5);
        r = Sync.badgeToAward(4, false, c);
        Test.assertEqual(r[0], "pw");
        Test.assertEqual(r[1], 5);
        r = Sync.badgeToAward(5, false, c);
        Test.assert(r[0] == null);
        Test.assertEqual(r[1], 5);
        r = Sync.badgeToAward(9, false, c);
        Test.assert(r[0] == null);
        Test.assertEqual(r[1], 9);
        r = Sync.badgeToAward(1, false, {"seq" => 2, "id" => "zz"});
        Test.assert(r[0] == null);
        Test.assertEqual(r[1], 2);
        return true;
    }

    (:test)
    function badgeSeqRestore(logger as Logger) as Boolean {
        Sync.restore(["d", 5, 7, "e"]);
        Test.assertEqual(Sync._lastBadgeSeq, 0);
        Sync.restore(["d", 5, 7, "e", "s", 1, 0, "", null, null, null, 8]);
        Test.assertEqual(Sync._lastBadgeSeq, 8);
        Sync.restore(["d", 5, 7, "e"]);
        Test.assertEqual(Sync._lastBadgeSeq, 0);
        return true;
    }
}
