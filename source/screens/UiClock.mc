// One 1 Hz heartbeat for the whole UI, driven by the Engine's own tick (Engine.onChange).
// Connect IQ allows only 3 timers at once and the backend already uses them (Engine, Sync,
// and Activities during a session), so screens must not start their own 1 s timers: a 4th timer
// crashes with "Too Many Timers". Instead the visible screen registers here on onShow and
// unregisters on onHide. This is the only user of Engine.onChange; the backend registers nothing there.
import Toybox.Lang;

module UiClock {
    var _listener as Method()? = null;
    var _owner as Object? = null;

    function start() as Void {
        Engine.onChange(new Lang.Method(UiClock, :onTick));
    }

    function stop() as Void {
        Engine.onChange(null);
        _listener = null;
        _owner = null;
    }

    // The screen that should get ticks; replaces any previous one.
    function listen(owner as Object, callback as Method()) as Void {
        _owner = owner;
        _listener = callback;
    }

    // Stops ticks for owner, unless another screen has taken over since.
    function release(owner as Object) as Void {
        if (_owner == owner) {
            _owner = null;
            _listener = null;
        }
    }

    function onTick() as Void {
        var st = Engine.state();
        Alerts.check(st);
        ScrollWatch.check(st);
        BadgeWatch.check(st);
        Notify.setSyncErr(st[:syncErr]);
        Notify.tick();
        var cb = _listener;
        if (cb != null) {
            cb.invoke();
        }
    }
}
