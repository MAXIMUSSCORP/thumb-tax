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
    var _info as Sensor.Info? = null;
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
        Records.load();
        Badges.load();
        Sync.start();
        Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE, Sensor.SENSOR_TEMPERATURE, Sensor.SENSOR_PULSE_OXIMETRY]);
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
        Sync.stop();
        closeSession();
        Ledger.save();
        Sync.save();
        Records.save();
        Badges.save();
        Sensor.enableSensorEvents(null);
        Sensor.setEnabledSensors([]);
    }

    function onSensor(info as Sensor.Info) as Void {
        _info = info;
        _hr = info.heartRate;
        _temp = info.temperature;
    }

    // The latest sensor reading; only one enableSensorEvents listener may exist, so the UI reads this.
    function lastInfo() as Sensor.Info? {
        return _info;
    }

    function hour() as Number {
        return System.getClockTime().hour;
    }

    function inBed() as Boolean {
        return _inBed;
    }

    function tick() as Void {
        var overBuzz = false;
        var scrolling = Sync.takeSecond();
        _hour = System.getClockTime().hour;
        var t = _temp;
        _inBed = t != null && t >= IN_BED_TEMP_C;
        if (scrolling) {
            if (_sessionSec == 0) {
                Records.openSession();
            }
            var charged = Ledger.chargeScroll(1, _hour, _inBed);
            _sessionSec += 1;
            _sessionCharged += charged;
            if (Ledger.isNight(_hour)) {
                _sessionNight = true;
            }
            var hr = _hr;
            Records.addScrollSecond(hr, charged);
            if (hr != null) {
                _hrSum += hr;
                _hrCount += 1;
            }
            if (Ledger.isOverdrawn()) {
                overBuzz = true;
            }
            _sinceSave += 1;
            if (_sinceSave >= SAVE_EVERY_SEC) {
                Ledger.save();
                Sync.save();
                Records.save();
                Badges.save();
                _sinceSave = 0;
            }
        } else if (_sessionSec > 0) {
            closeSession();
            Ledger.save();
            Sync.save();
            Records.save();
            Badges.save();
            _sinceSave = 0;
        }
        Badges.onTick(scrolling, Ledger.isOverdrawn(), Sync.isOnline() || Sync.manual() != null);
        if (Badges.takeBuzz()) {
            badgeVibrate();
        } else if (overBuzz) {
            vibrate();
        }
        var cb = _callback;
        if (cb != null) {
            cb.invoke();
        }
    }

    function closeSession() as Void {
        Records.closeSession();
        if (_sessionSec > 0) {
            Ledger.closeScrollSession(_sessionSec, _sessionCharged, _sessionNight);
            Badges.onScrollSessionEnd(_sessionSec);
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

    function badgeVibrate() as Void {
        if (Attention has :vibrate) {
            _lastVibeMs = System.getTimer();
            Attention.vibrate([
                new Attention.VibeProfile(100, 150), new Attention.VibeProfile(0, 100),
                new Attention.VibeProfile(100, 150), new Attention.VibeProfile(0, 100),
                new Attention.VibeProfile(100, 150)]);
        }
    }

    function onChange(callback as Method()?) as Void {
        _callback = callback;
    }

    function state() as Dictionary {
        var eff = Sync.effBalance(Ledger.balance(), Sync.pendingSec(), Ledger.multiplier(_hour, _inBed));
        return {
            :balanceSec => Ledger.balance(),
            :debtMin => eff < 0 ? (-eff + 59) / 60 : 0,
            :creditMin => eff > 0 ? eff / 60 : 0,
            :pendingSec => Sync.pendingSec(),
            :suggestion => Sync.suggestion(eff < 0 ? -eff : 0),
            :syncCode => Sync.lastError(),
            :syncFails => Sync.fails(),
            :syncErr => Sync.statusText(),
            :lastSyncAgoSec => Sync.lastSyncAgoSec(),
            :overdrawn => Ledger.isOverdrawn(),
            :scrolling => Sync.isScrolling(),
            :online => Sync.isOnline(),
            :manual => Sync.manual(),
            :night => Ledger.isNight(_hour),
            :inBed => _inBed,
            :multiplier => Ledger.multiplier(_hour, _inBed),
            :sessionSec => _sessionSec,
            :sessionChargedSec => _sessionCharged,
            :sessionAvgHr => _hrCount > 0 ? _hrSum / _hrCount : null,
            :hr => _hr,
            :tempC => _temp,
            :stats => Ledger.stats(),
            :streak => Badges.streak(),
            :unseenBadges => Badges.unseen().size()
        };
    }
}
