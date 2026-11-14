// Unit tests for the pure maths behind Activities (reps, tilt, pitch, variance, distance, climb gain).
import Toybox.Lang;
import Toybox.Test;

// One rep per period: baseline, dip below REP_LOW, spike above REP_HIGH, baseline.
function repWave(reps as Number, period as Number) as Array<Number> {
    var out = [] as Array<Number>;
    for (var r = 0; r < reps; r++) {
        for (var i = 0; i < period; i++) {
            var v = 1000;
            if (i == period / 4) {
                v = 500;
            } else if (i == period / 2) {
                v = 1500;
            }
            out.add(v);
        }
    }
    return out;
}

(:test)
function testCountRepsBasic(logger as Logger) as Boolean {
    return Activities.countReps(repWave(5, 50), {}, {:low => 700, :high => 1300, :minMs => 600, :perDetect => 1}) == 5;
}

(:test)
function testCountRepsMinInterval(logger as Logger) as Boolean {
    // 8-sample period = 320 ms per rep at 25 Hz, under the 600 ms floor
    var n = Activities.countReps(repWave(10, 8), {}, {:low => 700, :high => 1300, :minMs => 600, :perDetect => 1});
    return n < 10 && n >= 1;
}

(:test)
function testCountRepsCarryOver(logger as Logger) as Boolean {
    var all = repWave(4, 50);
    var st = {};
    var cut = 50 + 50 / 4 + 3; // mid-rep: after the dip, before the spike
    var a = Activities.countReps(all.slice(0, cut), st, {:low => 700, :high => 1300, :minMs => 600, :perDetect => 1});
    var b = Activities.countReps(all.slice(cut, null), st, {:low => 700, :high => 1300, :minMs => 600, :perDetect => 1});
    return a + b == 4;
}

(:test)
function testDistanceM(logger as Logger) as Boolean {
    var d = Activities.distanceM(0.0, 0.0, 1.0, 0.0);
    return (d - 111195.0).abs() < 1112.0;
}

(:test)
function testClimbGain(logger as Logger) as Boolean {
    var st = {};
    var total = 0.0;
    var alts = [100.0, 100.4, 99.8, 100.5, 100.2, 101.5, 103.0, 102.6, 104.0];
    for (var i = 0; i < alts.size(); i++) {
        total += Activities.climbGain(alts[i], st);
    }
    // sub-1 m wobble and dips never move the reference; rises 1.5 + 1.5 + 1.0
    return (total - 4.0).abs() < 0.01;
}

// Angle swings 0 -> 40 -> 0 once per period.
function tiltWave(reps as Number, period as Number) as Array<Float> {
    var out = [] as Array<Float>;
    for (var r = 0; r < reps; r++) {
        for (var i = 0; i < period; i++) {
            out.add((i >= period / 4 && i < period / 2) ? 40.0 : 0.0);
        }
    }
    return out;
}

(:test)
function testPitchDeg(logger as Logger) as Boolean {
    return Activities.pitchDeg(0, 0, 1000).abs() < 1.0
        && (Activities.pitchDeg(1000, 0, 0) - 90.0).abs() < 1.0;
}

(:test)
function testCountTiltThreeDips(logger as Logger) as Boolean {
    return Activities.countTilt(tiltWave(3, 50), {}, {:minDeg => 20, :minMs => 600, :perDetect => 1}) == 3;
}

(:test)
function testCountTiltMinMs(logger as Logger) as Boolean {
    // 8-sample period = 320 ms per dip at 25 Hz, under the 600 ms floor
    var n = Activities.countTilt(tiltWave(10, 8), {}, {:minDeg => 20, :minMs => 600, :perDetect => 1});
    return n >= 1 && n < 10;
}

(:test)
function testPerDetectDoubles(logger as Logger) as Boolean {
    var p = {:low => 700, :high => 1300, :minMs => 600, :perDetect => 2};
    return Activities.countReps(repWave(5, 50), {}, p) == 10;
}

(:test)
function testVarianceConstant(logger as Logger) as Boolean {
    return Activities.variance([1000, 1000, 1000, 1000]) == 0.0;
}
