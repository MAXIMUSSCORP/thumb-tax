// Sensor-verifies earn activities from the Catalog with one table-driven detector engine
// and credits what was proven through Ledger. No views, no WatchUi.
import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Timer;
import Toybox.Sensor;
import Toybox.Position;
import Toybox.ActivityMonitor;
import Toybox.UserProfile;

module Activities {

    const ACCEL_HZ = 25;
    const NO_ACCEL_TIMEOUT_SEC = 3;
    const MAX_JUMP_M = 100.0;
    const CLIMB_STEP_M = 1.0;
    const EARTH_RADIUS_M = 6371000.0;
    const VAR_WINDOW = 4;               // 1 Hz samples, a few seconds of motion history
    const DEFAULT_RESTING_HR = 60;
    const HR_EDGE_SEC = 30;
    const STEP_WINDOW = 10;             // seconds of step history for cadence
    const CADENCE_FALLBACK_VAR = 10000; // milli-g^2: stand-in when the step counter never moves
    const TILT_BASE_ALPHA = 0.05;

    // Modules have no method(); this tiny class owns the callbacks.
    class Callbacks {
        function onAccel(data as Sensor.SensorData) as Void { Activities.onAccel(data); }
        function onPosition(info as Position.Info) as Void { Activities.onPosition(info); }
        function onTick() as Void { Activities.onTick(); }
    }
    var _cb = new Callbacks();

    var _kind as Symbol or Null = null;
    var _entry as Dictionary or Null = null;
    var _det as Symbol or Null = null;
    var _params as Dictionary = {};
    var _startSec as Number = 0;
    var _count as Number = 0;
    var _estimated as Boolean = false;
    var _valid as Boolean = true;
    var _hint as String = "";
    var _timer as Timer.Timer or Null = null;

    var _repState as Dictionary = {};
    var _gotAccel as Boolean = false;
    var _mags as Array<Number> = [];
    var _steps as Array<Number> = [];

    var _hrFirstSum as Number = 0;
    var _hrFirstN as Number = 0;
    var _hrLast as Array<Number> = [];

    var _startTemp as Float or Null = null;
    var _startHr as Number or Null = null;
    var _fixOk as Boolean = false;

    var _distM as Float = 0.0;
    var _climbM as Float = 0.0;
    var _lastLat as Double or Null = null;
    var _lastLon as Double or Null = null;
    var _climbState as Dictionary = {};
    var _floorsStart as Number = 0;

    function pn(p as Dictionary, k as Symbol, def as Numeric) as Numeric {
        return p.hasKey(k) ? p[k] as Numeric : def;
    }

    // Counts reps in a batch of accel magnitudes (milli-g); st carries state across batches.
    // params: :low, :high, :minMs, :perDetect.
    function countReps(samples as Array<Number>, st as Dictionary, params as Dictionary) as Number {
        var low = pn(params, :low, 700);
        var high = pn(params, :high, 1300);
        var gap = pn(params, :minMs, 600).toNumber() * ACCEL_HZ / 1000;
        var idx = st.hasKey(:idx) ? st[:idx] as Number : 0;
        var last = st.hasKey(:last) ? st[:last] as Number : -gap;
        var armed = st.hasKey(:armed) ? st[:armed] as Boolean : false;
        var reps = 0;
        for (var i = 0; i < samples.size(); i++) {
            var s = samples[i];
            if (s < low) {
                armed = true;
            } else if (s > high && armed) {
                armed = false;
                if (idx - last >= gap) {
                    reps++;
                    last = idx;
                }
            }
            idx++;
        }
        st[:idx] = idx;
        st[:last] = last;
        st[:armed] = armed;
        return reps * pn(params, :perDetect, 1).toNumber();
    }

    // Forearm pitch against gravity in degrees: 0 when x is level, 90 when x points along gravity.
    function pitchDeg(x as Numeric, y as Numeric, z as Numeric) as Float {
        var flat = Math.sqrt(y * y + z * z);
        return (Math.atan2(x, flat) * 180.0 / Math.PI).toFloat();
    }

    // Counts planted-hand reps from pitch angles: away from the rolling baseline by :minDeg, then back.
    // params: :minDeg, :minMs, :perDetect.
    function countTilt(angles as Array<Float>, st as Dictionary, params as Dictionary) as Number {
        var minDeg = pn(params, :minDeg, 20).toFloat();
        var gap = pn(params, :minMs, 600).toNumber() * ACCEL_HZ / 1000;
        var idx = st.hasKey(:idx) ? st[:idx] as Number : 0;
        var last = st.hasKey(:last) ? st[:last] as Number : -gap;
        var away = st.hasKey(:away) ? st[:away] as Boolean : false;
        var base = st.hasKey(:base) ? st[:base] as Float : angles.size() > 0 ? angles[0] : 0.0;
        var reps = 0;
        for (var i = 0; i < angles.size(); i++) {
            var a = angles[i];
            var dev = (a - base).abs();
            if (dev >= minDeg) {
                away = true;
            } else if (away && dev < minDeg / 2) {
                away = false;
                if (idx - last >= gap) {
                    reps++;
                    last = idx;
                }
            }
            if (!away) {
                base += (a - base) * TILT_BASE_ALPHA;
            }
            idx++;
        }
        st[:idx] = idx;
        st[:last] = last;
        st[:away] = away;
        st[:base] = base;
        return reps * pn(params, :perDetect, 1).toNumber();
    }

    function variance(a as Array<Number>) as Float {
        if (a.size() == 0) {
            return 0.0;
        }
        var sum = 0.0;
        for (var i = 0; i < a.size(); i++) {
            sum += a[i];
        }
        var mean = sum / a.size();
        var v = 0.0;
        for (var i = 0; i < a.size(); i++) {
            v += (a[i] - mean) * (a[i] - mean);
        }
        return v / a.size();
    }

    function distanceM(lat1 as Numeric, lon1 as Numeric, lat2 as Numeric, lon2 as Numeric) as Float {
        var k = Math.PI / 180.0;
        var dLat = (lat2 - lat1) * k;
        var dLon = (lon2 - lon1) * k;
        var a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
            + Math.cos(lat1 * k) * Math.cos(lat2 * k) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
        return (EARTH_RADIUS_M * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))).toFloat();
    }

    // Returns metres of new climb for this altitude reading; st holds the reference altitude.
    function climbGain(alt as Numeric, st as Dictionary) as Float {
        if (!st.hasKey(:ref)) {
            st[:ref] = alt;
            return 0.0;
        }
        var ref = st[:ref] as Numeric;
        if (alt < ref - CLIMB_STEP_M) {
            st[:ref] = alt;
        } else if (alt - ref >= CLIMB_STEP_M) {
            st[:ref] = alt;
            return (alt - ref).toFloat();
        }
        return 0.0;
    }

    function restingHr() as Number {
        var p = UserProfile.getProfile();
        if (p != null && p.restingHeartRate != null) {
            return p.restingHeartRate as Number;
        }
        return DEFAULT_RESTING_HR;
    }

    // UserProfile.wakeTime is a Duration since local midnight.
    function inWakeWindow(hours as Numeric) as Boolean {
        var p = UserProfile.getProfile();
        if (p == null || p.wakeTime == null) {
            return true; // no wake time on this device: skip the check
        }
        var t = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var nowSec = t.hour * 3600 + t.min * 60 + t.sec;
        var since = (nowSec - (p.wakeTime as Time.Duration).value() + 86400) % 86400;
        return since <= hours * 3600;
    }

    function start(kind as Symbol) as Boolean {
        if (_kind != null) {
            return false;
        }
        var e = Catalog.get(kind);
        if (e == null) {
            return false;
        }
        if (e[:daily] == true && Ledger.claimedToday(kind)) {
            return false;
        }
        var det = e[:detector] as Symbol;
        var p = e[:params] as Dictionary;
        var wake = pn(p, :wakeWindowH, 0);
        if (det == :outdoors && wake > 0 && !inWakeWindow(wake)) {
            return false;
        }
        _kind = kind;
        _entry = e;
        _det = det;
        _params = p;
        _startSec = Time.now().value();
        _count = 0;
        _estimated = false;
        _valid = true;
        _hint = "";
        _repState = {};
        _gotAccel = false;
        _mags = [];
        _steps = [];
        _hrFirstSum = 0;
        _hrFirstN = 0;
        _hrLast = [];
        _startTemp = null;
        _startHr = null;
        _fixOk = false;
        _distM = 0.0;
        _climbM = 0.0;
        _lastLat = null;
        _lastLon = null;
        _climbState = {};

        if (det == :reps || det == :tilt) {
            _hint = "Start moving";
            try {
                Sensor.registerSensorDataListener(_cb.method(:onAccel),
                    {:period => 1, :accelerometer => {:enabled => true, :sampleRate => ACCEL_HZ}});
            } catch (ex) {
                _estimated = true;
                _hint = "No motion data. Tap to count reps.";
            }
        } else if (det == :walk || det == :outdoors) {
            _hint = "Waiting for GPS";
            Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, _cb.method(:onPosition));
        } else if (det == :floors) {
            _floorsStart = floorsNow();
            _hint = "Climb stairs";
        } else {
            _hint = "Starting";
        }
        if (det != :walk && det != :floors) {
            _timer = new Timer.Timer();
            _timer.start(_cb.method(:onTick), 1000, true);
        }
        Badges.onActivityStart(kind);
        return true;
    }

    function stop() as Number {
        if (_kind == null) {
            return 0;
        }
        var kind = _kind as Symbol;
        var det = _det;
        var p = _params;
        var minSec = (_entry as Dictionary)[:minSec];
        var info = progress();
        var elapsed = info[:elapsedSec] as Number;
        var hrDrop = hrDropped(p, elapsed);
        teardown();
        if (minSec != null && elapsed < (minSec as Number)) {
            return 0;
        }
        var n = info[:count] as Number;
        if (det == :walk) {
            var walked = Ledger.earn(:walkM, n) + Ledger.earn(:climbM, info[:climbM] as Number);
            if (walked > 0) {
                Badges.onActivityCredited(kind, walked);
            }
            return walked;
        }
        var credited = Ledger.earn(kind, n);
        if (hrDrop && credited > 0) {
            credited += Ledger.bonus(pn(p, :hrDropBonusSec, 0).toNumber(), "heart rate fell");
        }
        if (credited > 0) {
            Badges.onActivityCredited(kind, credited);
        }
        return credited;
    }

    // :calm sessions earn a bonus when the last 30 s average HR is :hrDropBpm below the first 30 s.
    function hrDropped(p as Dictionary, elapsed as Number) as Boolean {
        if (pn(p, :hrDropBonusSec, 0) <= 0 || _hrFirstN == 0 || _hrLast.size() == 0
            || elapsed < 2 * HR_EDGE_SEC) {
            return false;
        }
        var last = 0;
        for (var i = 0; i < _hrLast.size(); i++) {
            last += _hrLast[i];
        }
        var first = _hrFirstSum.toFloat() / _hrFirstN;
        return first - last.toFloat() / _hrLast.size() >= pn(p, :hrDropBpm, 5);
    }

    function cancel() as Void {
        teardown();
    }

    function running() as Symbol or Null {
        return _kind;
    }

    function progress() as Dictionary {
        var count = _count;
        if (_det == :walk) {
            count = _distM.toNumber();
        } else if (_det == :floors) {
            count = floorsNow() - _floorsStart;
            if (count < 0) {
                count = 0;
            }
        }
        var e = _entry;
        return {
            :kind => _kind,
            :label => (e == null) ? "" : e[:label],
            :unit => (e == null) ? null : e[:unit],
            :elapsedSec => (_kind == null) ? 0 : Time.now().value() - _startSec,
            :count => count,
            :climbM => _climbM.toNumber(),
            :valid => _valid,
            :estimated => _estimated,
            :hint => _hint
        };
    }

    function tapRep() as Void {
        if (_det == :reps || _det == :tilt) {
            _count += pn(_params, :perDetect, 1).toNumber();
            _estimated = true;
        }
    }

    function teardown() as Void {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
        if (_det == :reps || _det == :tilt) {
            try {
                Sensor.unregisterSensorDataListener();
            } catch (ex) {
            }
        } else if (_det == :walk || _det == :outdoors) {
            Position.enableLocationEvents(Position.LOCATION_DISABLE, _cb.method(:onPosition));
        }
        _kind = null;
        _entry = null;
        _det = null;
        _hint = "";
    }

    function floorsNow() as Number {
        var info = ActivityMonitor.getInfo();
        if (info == null || info.floorsClimbed == null) {
            return 0;
        }
        return info.floorsClimbed as Number;
    }

    function onAccel(data as Sensor.SensorData) as Void {
        var a = data.accelerometerData;
        if (a == null || a.x == null || a.y == null || a.z == null
            || (_det != :reps && _det != :tilt)) {
            return;
        }
        var xs = a.x as Array<Number>;
        var ys = a.y as Array<Number>;
        var zs = a.z as Array<Number>;
        _gotAccel = true;
        _hint = "Counting";
        var n = xs.size();
        if (_det == :reps) {
            var mags = [] as Array<Number>;
            for (var i = 0; i < n; i++) {
                mags.add(Math.sqrt(xs[i] * xs[i] + ys[i] * ys[i] + zs[i] * zs[i]).toNumber());
            }
            _count += countReps(mags, _repState, _params);
        } else {
            var angles = [] as Array<Float>;
            for (var i = 0; i < n; i++) {
                angles.add(pitchDeg(xs[i], ys[i], zs[i]));
            }
            _count += countTilt(angles, _repState, _params);
        }
    }

    function onPosition(info as Position.Info) as Void {
        if (_det != :walk && _det != :outdoors) {
            return;
        }
        var q = info.accuracy;
        var pos = info.position;
        _fixOk = (q != null && q >= Position.QUALITY_USABLE && pos != null);
        if (!_fixOk) {
            _hint = "Waiting for GPS";
            return;
        }
        if (_det == :outdoors) {
            return;
        }
        _hint = "Walking";
        var deg = (pos as Position.Location).toDegrees();
        var lat = deg[0];
        var lon = deg[1];
        if (_lastLat != null && _lastLon != null) {
            var d = distanceM(_lastLat, _lastLon, lat, lon);
            if (d > MAX_JUMP_M) {
                _lastLat = lat;
                _lastLon = lon;
                return;
            }
            _distM += d;
        }
        _lastLat = lat;
        _lastLon = lon;

        var alt = Sensor.getInfo().altitude; // barometric when available
        if (alt == null) {
            alt = info.altitude;
        }
        if (alt != null) {
            _climbM += climbGain(alt, _climbState);
        }
    }

    // Pushes this second's accel magnitude and returns variance, or null when accel is missing.
    function sampleVar(accel as Array<Number> or Null) as Float or Null {
        if (accel == null || accel.size() < 3) {
            return null;
        }
        var mag = Math.sqrt(accel[0] * accel[0] + accel[1] * accel[1] + accel[2] * accel[2]).toNumber();
        _mags.add(mag);
        if (_mags.size() > VAR_WINDOW) {
            _mags = _mags.slice(1, null);
        }
        return (_mags.size() >= 3) ? variance(_mags) : 0.0;
    }

    function trackHr(hr as Number or Null, elapsed as Number) as Void {
        if (hr == null) {
            return;
        }
        if (elapsed < HR_EDGE_SEC) {
            _hrFirstSum += hr;
            _hrFirstN++;
        }
        _hrLast.add(hr);
        if (_hrLast.size() > HR_EDGE_SEC) {
            _hrLast = _hrLast.slice(1, null);
        }
    }

    // Rough pose from gravity on the watch z axis (face normal), milli-g. Estimated, not a true pose.
    function poseOk(pose as Symbol, accel as Array<Number>) as Boolean {
        var z = accel[2];
        return (pose == :supine) ? z > 700 : z < 600;
    }

    function stepsPerMin() as Number {
        var info = ActivityMonitor.getInfo();
        if (info == null || info.steps == null) {
            return 0;
        }
        _steps.add(info.steps as Number);
        if (_steps.size() > STEP_WINDOW + 1) {
            _steps = _steps.slice(1, null);
        }
        if (_steps.size() < 2) {
            return 0;
        }
        return (_steps[_steps.size() - 1] - _steps[0]) * 60 / (_steps.size() - 1);
    }

    function onTick() as Void {
        var det = _det;
        if (_kind == null || det == null) {
            return;
        }
        var elapsed = Time.now().value() - _startSec;
        if (det == :reps || det == :tilt) {
            if (!_gotAccel && elapsed >= NO_ACCEL_TIMEOUT_SEC) {
                _estimated = true;
                _hint = "No motion data. Tap to count reps.";
            }
            return;
        }
        if (det == :walk || det == :floors) {
            return;
        }
        var info = Sensor.getInfo();
        var hr = info.heartRate;
        var accel = info.accel;
        var v = sampleVar(accel);
        var p = _params;
        var hrReq = pn(p, :hrAbove, pn(p, :needHrAbove, 0));
        var hrOk = (hrReq == 0 || hr == null || hr >= restingHr() + hrReq);
        if ((v == null && det != :cold && det != :outdoors && det != :cadence)
            || (hr == null && hrReq > 0)) {
            _estimated = true; // missing sensor: the other signal decides
        }
        var ok = false;
        var why = "";
        var extra = "";
        if (det == :calm) {
            trackHr(hr, elapsed);
            var maxHr = pn(p, :maxHr, 90);
            ok = (hr != null || v != null) && (hr == null || hr < maxHr)
                && (v == null || v <= pn(p, :maxVar, 2500));
            if (hr == null || v == null) {
                _estimated = true;
            }
            why = (hr != null && hr >= maxHr) ? "Heart rate too high" : "Hold still";
        } else if (det == :hold) {
            ok = v != null && v <= pn(p, :maxVar, 2500)
                && (accel == null || accel.size() < 3 || poseOk(p[:pose] as Symbol, accel));
            why = "Hold the pose still";
        } else if (det == :active || det == :vigorous) {
            ok = (hr != null || v != null) && (v == null || v >= pn(p, :minVar, 5000)) && hrOk;
            if (hr == null || v == null) {
                _estimated = true;
            }
            why = hrOk ? "Keep moving" : "Raise your heart rate";
        } else if (det == :cadence) {
            var spm = stepsPerMin();
            var fallback = (spm == 0 && v != null && v >= CADENCE_FALLBACK_VAR);
            if (fallback) {
                _estimated = true;
            }
            var hrFallback = (spm == 0 && v == null && hrReq > 0 && hr != null
                && hr >= restingHr() + hrReq);
            if (hrFallback) {
                _estimated = true;
            }
            ok = (spm >= pn(p, :minSpm, 100) || fallback || hrFallback) && hrOk;
            why = (spm == 0 && v == null && hrReq == 0) ? "No step or motion data" : "Step faster";
        } else if (det == :cold) {
            var t = info.temperature;
            if (t == null) {
                _estimated = true;
            } else if (_startTemp == null) {
                _startTemp = t.toFloat();
            }
            if (hr != null && _startHr == null) {
                _startHr = hr;
            }
            if (t != null) {
                ok = (_startTemp != null && t <= _startTemp - pn(p, :dropC, 2));
            } else {
                ok = (hr != null && _startHr != null && hr >= _startHr + pn(p, :hrSpike, 10));
            }
            why = "Wait for the cold";
            if (ok && hr != null && _startHr != null && hr >= _startHr + pn(p, :hrSpike, 10)) {
                extra = "Cold shock detected";
            }
        } else if (det == :outdoors) {
            ok = _fixOk && hrOk;
            why = _fixOk ? "Raise your heart rate" : "Waiting for GPS";
        }
        _valid = ok;
        if (ok) {
            _count++;
            _hint = (extra.length() > 0) ? extra : "Counting";
        } else {
            _hint = why;
        }
    }
}
