// Verifies "punishment" activities (push-ups, walking, stairs, reading) with real sensors
// and turns what was proven into credit via Ledger. No views, no WatchUi.
import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;
import Toybox.Timer;
import Toybox.Sensor;
import Toybox.Position;
import Toybox.ActivityMonitor;

module Activities {

    const REP_LOW = 700;            // milli-g: arm below this
    const REP_HIGH = 1300;          // milli-g: count when back above this
    const REP_MIN_GAP_MS = 600;
    const ACCEL_HZ = 25;
    const NO_ACCEL_TIMEOUT_SEC = 3;
    const MAX_JUMP_M = 100.0;
    const CLIMB_STEP_M = 1.0;
    const EARTH_RADIUS_M = 6371000.0;
    const READING_MAX_HR = 90;
    const READING_STILL_VAR = 2500; // milli-g^2 over the window (~50 mg std dev)
    const READING_WINDOW = 4;

    // Modules have no method(); this tiny class owns the callbacks.
    class Callbacks {
        function onAccel(data as Sensor.SensorData) as Void { Activities.onAccel(data); }
        function onPosition(info as Position.Info) as Void { Activities.onPosition(info); }
        function onTick() as Void { Activities.onTick(); }
    }
    var _cb = new Callbacks();

    var _kind as Symbol or Null = null;
    var _startSec as Number = 0;
    var _count as Number = 0;
    var _estimated as Boolean = false;
    var _valid as Boolean = true;
    var _hint as String = "";
    var _timer as Timer.Timer or Null = null;

    var _repState as Dictionary = {};
    var _gotAccel as Boolean = false;

    var _distM as Float = 0.0;
    var _climbM as Float = 0.0;
    var _lastLat as Double or Null = null;
    var _lastLon as Double or Null = null;
    var _climbState as Dictionary = {};

    var _floorsStart as Number = 0;
    var _mags as Array<Number> = [];

    // Counts reps in a batch of accel samples (milli-g); state in st carries across batches.
    function countReps(samples as Array<Number>, st as Dictionary) as Number {
        var gap = REP_MIN_GAP_MS * ACCEL_HZ / 1000;
        var idx = st.hasKey(:idx) ? st[:idx] as Number : 0;
        var last = st.hasKey(:last) ? st[:last] as Number : -gap;
        var armed = st.hasKey(:armed) ? st[:armed] as Boolean : false;
        var reps = 0;
        for (var i = 0; i < samples.size(); i++) {
            var s = samples[i];
            if (s < REP_LOW) {
                armed = true;
            } else if (s > REP_HIGH && armed) {
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
        return reps;
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

    function start(kind as Symbol) as Boolean {
        if (_kind != null) {
            return false;
        }
        if (kind != :pushups && kind != :walk && kind != :stairs && kind != :reading) {
            return false;
        }
        _kind = kind;
        _startSec = Time.now().value();
        _count = 0;
        _estimated = false;
        _valid = true;
        _hint = "";
        _repState = {};
        _gotAccel = false;
        _distM = 0.0;
        _climbM = 0.0;
        _lastLat = null;
        _lastLon = null;
        _climbState = {};
        _mags = [];

        if (kind == :pushups) {
            _hint = "Start pushing";
            try {
                Sensor.registerSensorDataListener(_cb.method(:onAccel),
                    {:period => 1, :accelerometer => {:enabled => true, :sampleRate => ACCEL_HZ}});
            } catch (e) {
                _estimated = true;
                _hint = "No motion data. Tap to count reps.";
            }
        } else if (kind == :walk) {
            _hint = "Waiting for GPS";
            Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, _cb.method(:onPosition));
        } else if (kind == :stairs) {
            _floorsStart = floorsNow();
            _hint = "Climb stairs";
        } else {
            _hint = "Hold still to keep reading";
        }
        if (kind == :pushups || kind == :reading) {
            _timer = new Timer.Timer();
            _timer.start(_cb.method(:onTick), 1000, true);
        }
        return true;
    }

    function stop() as Number {
        if (_kind == null) {
            return 0;
        }
        var kind = _kind;
        var credited = 0;
        var info = progress();
        teardown();
        var n = info[:count] as Number;
        if (kind == :pushups) {
            credited = Ledger.earn(:pushups, n);
        } else if (kind == :stairs) {
            credited = Ledger.earn(:floors, n);
        } else if (kind == :reading) {
            credited = Ledger.earn(:readingSec, n);
        } else {
            credited = Ledger.earn(:walkM, n) + Ledger.earn(:climbM, info[:climbM] as Number);
        }
        return credited;
    }

    function cancel() as Void {
        teardown();
    }

    function running() as Symbol or Null {
        return _kind;
    }

    function progress() as Dictionary {
        var count = _count;
        if (_kind == :walk) {
            count = _distM.toNumber();
        } else if (_kind == :stairs) {
            count = floorsNow() - _floorsStart;
            if (count < 0) {
                count = 0;
            }
        }
        var elapsed = (_kind == null) ? 0 : Time.now().value() - _startSec;
        return {
            :kind => _kind,
            :elapsedSec => elapsed,
            :count => count,
            :climbM => _climbM.toNumber(),
            :valid => _valid,
            :estimated => _estimated,
            :hint => _hint
        };
    }

    function tapRep() as Void {
        if (_kind == :pushups) {
            _count++;
            _estimated = true;
        }
    }

    function teardown() as Void {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
        if (_kind == :pushups) {
            try {
                Sensor.unregisterSensorDataListener();
            } catch (e) {
            }
        } else if (_kind == :walk) {
            Position.enableLocationEvents(Position.LOCATION_DISABLE, _cb.method(:onPosition));
        }
        _kind = null;
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
        if (a == null || _kind != :pushups) {
            return;
        }
        _gotAccel = true;
        _hint = "Start pushing";
        _count += countReps(a.z as Array<Number>, _repState);
    }

    function onPosition(info as Position.Info) as Void {
        if (_kind != :walk) {
            return;
        }
        var q = info.accuracy;
        var pos = info.position;
        if (q == null || q < Position.QUALITY_USABLE || pos == null) {
            _hint = "Waiting for GPS";
            return;
        }
        _hint = "Walking";
        var deg = pos.toDegrees();
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

    function onTick() as Void {
        if (_kind == :pushups) {
            if (!_gotAccel && Time.now().value() - _startSec >= NO_ACCEL_TIMEOUT_SEC) {
                _estimated = true;
                _hint = "No motion data. Tap to count reps.";
            }
        } else if (_kind == :reading) {
            tickReading();
        }
    }

    function tickReading() as Void {
        var info = Sensor.getInfo();
        var hr = info.heartRate;
        var calm = (hr == null || hr < READING_MAX_HR);
        var still = true;
        var accel = info.accel;
        if (accel != null && accel.size() >= 3) {
            var mag = Math.sqrt(accel[0] * accel[0] + accel[1] * accel[1] + accel[2] * accel[2]).toNumber();
            _mags.add(mag);
            if (_mags.size() > READING_WINDOW) {
                _mags = _mags.slice(1, null);
            }
            if (_mags.size() >= 3) {
                var sum = 0;
                for (var i = 0; i < _mags.size(); i++) {
                    sum += _mags[i];
                }
                var mean = sum / _mags.size();
                var v = 0;
                for (var i = 0; i < _mags.size(); i++) {
                    v += (_mags[i] - mean) * (_mags[i] - mean);
                }
                still = (v / _mags.size()) < READING_STILL_VAR;
            }
        } else {
            _estimated = true; // no accel: HR alone decides
        }
        _valid = calm && still;
        if (_valid) {
            _count++;
            _hint = "Reading counts";
        } else {
            _hint = calm ? "Hold still to keep reading" : "Heart rate too high";
        }
    }
}
