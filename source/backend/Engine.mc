// Why this exists: the 1 Hz heartbeat that turns "user is scrolling" into ledger charges.
// The UI only reads Engine.state() and registers one change callback.
import Toybox.Attention;
import Toybox.Lang;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Timer;

// Estimated, not measured: a wrist under a blanket runs warm, so skin temp >= this means "in bed".
const IN_BED_TEMP_C = 33.0;
const SAVE_EVERY_SEC = 30;
const VIBE_EVERY_MS = 10000;

module Engine {
    var _timer as Timer.Timer? = null;
    var _callback as Method()? = null;
    var _hr as Number? = null;
    var _temp as Float? = null;
    var _hour as Number = 0;
    var _inBed as Boolean = false;
    var _sessionSec as Number = 0;
    var _sessionCharged as Number = 0;
    var _sessionNight as Boolean = false;
    var _hrSum as Number = 0;
    var _hrCount as Number = 0;
    var _sinceSave as Number = 0;
    var _lastVibeMs as Number = -VIBE_EVERY_MS;

    function start() as Void {
        if (_timer != null) {
            return;
        }
        Ledger.load();
        ScrollSource.start();
        Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE, Sensor.SENSOR_TEMPERATURE]);
        Sensor.enableSensorEvents(new Lang.Method(Engine, :onSensor));
        var t = new Timer.Timer();
        _timer = t;
        t.start(new Lang.Method(Engine, :tick), 1000, true);
    }

    function stop() as Void {
        var t = _timer;
        if (t != null) {
            t.stop();
        }
        _timer = null;
        ScrollSource.stop();
        closeSession();
        Ledger.save();
        Sensor.enableSensorEvents(null);
        Sensor.setEnabledSensors([]);
    }

    function onSensor(info as Sensor.Info) as Void {
        _hr = info.heartRate;
        _temp = info.temperature;
    }

    function tick() as Void {
        _hour = System.getClockTime().hour;
        var t = _temp;
        _inBed = t != null && t >= IN_BED_TEMP_C;
        if (ScrollSource.isScrolling()) {
            var charged = Ledger.chargeScroll(1, _hour, _inBed);
            _sessionSec += 1;
            _sessionCharged += charged;
            if (Ledger.isNight(_hour)) {
                _sessionNight = true;
            }
            var hr = _hr;
            if (hr != null) {
                _hrSum += hr;
                _hrCount += 1;
            }
            if (Ledger.isOverdrawn()) {
                vibrate();
            }
            _sinceSave += 1;
            if (_sinceSave >= SAVE_EVERY_SEC) {
                Ledger.save();
                _sinceSave = 0;
            }
        } else if (_sessionSec > 0) {
            closeSession();
            Ledger.save();
            _sinceSave = 0;
        }
        var cb = _callback;
        if (cb != null) {
            cb.invoke();
        }
    }

    function closeSession() as Void {
        if (_sessionSec > 0) {
            Ledger.closeScrollSession(_sessionSec, _sessionCharged, _sessionNight);
        }
        _sessionSec = 0;
        _sessionCharged = 0;
        _sessionNight = false;
        _hrSum = 0;
        _hrCount = 0;
    }

    function vibrate() as Void {
        var now = System.getTimer();
        if (now - _lastVibeMs < VIBE_EVERY_MS) {
            return;
        }
        if (Attention has :vibrate) {
            _lastVibeMs = now;
            Attention.vibrate([new Attention.VibeProfile(100, 400)]);
        }
    }

    function onChange(callback as Method()?) as Void {
        _callback = callback;
    }

    function state() as Dictionary {
        return {
            :balanceSec => Ledger.balance(),
            :overdrawn => Ledger.isOverdrawn(),
            :scrolling => ScrollSource.isScrolling(),
            :online => ScrollSource.isOnline(),
            :manual => ScrollSource.manual(),
            :night => Ledger.isNight(_hour),
            :inBed => _inBed,
            :multiplier => Ledger.multiplier(_hour, _inBed),
            :sessionSec => _sessionSec,
            :sessionChargedSec => _sessionCharged,
            :sessionAvgHr => _hrCount > 0 ? _hrSum / _hrCount : null,
            :hr => _hr,
            :tempC => _temp,
            :stats => Ledger.stats()
        };
    }
}
