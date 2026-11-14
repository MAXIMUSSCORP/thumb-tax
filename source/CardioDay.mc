// Today's heart rate in 15-minute bins from the watch's own history, split into scrolling vs not scrolling.
// The heart rate is real when the watch has history; the scroll sessions come from Records (demo data until real sessions exist).
import Toybox.Lang;
import Toybox.Math;
import Toybox.SensorHistory;
import Toybox.Time;

class CardioDay {
    public const BINS = 96;

    public var bins as Array<Float or Null>;
    public var restAvg as Float or Null = null;
    public var scrollAvg as Float or Null = null;
    // True when the watch had no history and the curve is generated.
    public var demo as Boolean = false;

    public function initialize() {
        bins = new Array<Float or Null>[BINS];
    }

    public function lift() as Number or Null {
        var s = scrollAvg;
        var r = restAvg;
        return (s != null && r != null) ? Math.round(s - r).toNumber() : null;
    }

    private function inAny(sessions as Array<Array<Number> >, minute as Number) as Boolean {
        for (var i = 0; i < sessions.size(); i++) {
            var s = sessions[i];
            if (minute >= s[0] && minute <= s[1]) {
                return true;
            }
        }
        return false;
    }

    public function load() as Void {
        var sessions = Records.todaySessions();
        var sums = new Array<Float>[BINS];
        var counts = new Array<Number>[BINS];
        for (var i = 0; i < BINS; i++) {
            sums[i] = 0.0;
            counts[i] = 0;
            bins[i] = null;
        }
        var midnight = Time.today();
        var secs = Time.now().value() - midnight.value();
        var nowBin = secs / 900;

        var inSum = 0.0;
        var inN = 0;
        var outSum = 0.0;
        var outN = 0;

        if (secs > 0 && (Toybox has :SensorHistory) && (SensorHistory has :getHeartRateHistory)) {
            var it = SensorHistory.getHeartRateHistory({
                :period => new Time.Duration(secs),
                :order => SensorHistory.ORDER_OLDEST_FIRST
            });
            var s = it.next();
            while (s != null) {
                var v = s.data;
                var when = s.when;
                if (v != null && when != null && v > 0 && v < 250) {
                    var minute = (when.value() - midnight.value()) / 60;
                    if (minute >= 0 && minute < 1440) {
                        var b = minute / 15;
                        sums[b] += v.toFloat();
                        counts[b] += 1;
                        if (inAny(sessions, minute)) {
                            inSum += v.toFloat();
                            inN += 1;
                        } else {
                            outSum += v.toFloat();
                            outN += 1;
                        }
                    }
                }
                s = it.next();
            }
        }

        demo = (inN + outN) == 0;
        if (demo) {
            // Generated curve: low overnight, higher by day, lifted during scroll sessions.
            for (var b = 0; b <= nowBin && b < BINS; b++) {
                var minute = b * 15 + 7;
                var day = (Math.sin(minute / 1440.0 * 2 * Math.PI - Math.PI / 2) + 1) / 2;
                var hr = 56 + 18 * day + 3 * Math.sin(b * 1.7);
                var scrolling = false;
                for (var m = b * 15; m < b * 15 + 15; m++) {
                    if (inAny(sessions, m)) {
                        scrolling = true;
                        break;
                    }
                }
                if (scrolling) {
                    hr += 9;
                    inSum += hr;
                    inN += 1;
                } else {
                    outSum += hr;
                    outN += 1;
                }
                sums[b] = hr.toFloat();
                counts[b] = 1;
            }
        }

        for (var i = 0; i < BINS; i++) {
            if (counts[i] > 0) {
                bins[i] = sums[i] / counts[i];
            }
        }
        restAvg = (outN > 0) ? outSum / outN : null;
        scrollAvg = (inN > 0) ? inSum / inN : null;
    }

    public function range() as [Float, Float] {
        var lo = 999.0;
        var hi = 0.0;
        for (var i = 0; i < BINS; i++) {
            var v = bins[i];
            if (v != null) {
                if (v < lo) { lo = v; }
                if (v > hi) { hi = v; }
            }
        }
        if (hi < lo) {
            return [50.0, 100.0];
        }
        return [lo - 5.0, hi + 5.0];
    }
}
