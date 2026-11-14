// Banner notifications drawn over whichever screen is on top ("TIME ADDED", "TIME'S UP", "TIME OUT", ...).
// Every screen calls Notify.draw(dc) at the end of onUpdate; UiClock calls Notify.tick() once a second
// so the banner disappears on time. No timers of its own (the device timer budget belongs to the backend).
import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

module Notify {
    const SHOW_MS = 3000;

    var _title as String? = null;
    var _sub as String? = null;
    var _until as Number = 0;

    // Shows a banner; vibe = true also buzzes briefly.
    function show(title as String, sub as String?, vibe as Boolean) as Void {
        _title = title;
        _sub = sub;
        _until = System.getTimer() + SHOW_MS;
        if (vibe && (Attention has :vibrate)) {
            Attention.vibrate([new Attention.VibeProfile(60, 250)]);
        }
        WatchUi.requestUpdate();
    }

    function active() as Boolean {
        return _title != null && System.getTimer() < _until;
    }

    // Clears an expired banner and redraws so it leaves the screen.
    function tick() as Void {
        if (_title != null) {
            if (!active()) {
                _title = null;
                _sub = null;
            }
            WatchUi.requestUpdate();
        }
    }

    // White card with a black rim, so it stands out on both the black screens and the white overdraft page.
    function draw(dc as Dc) as Void {
        var title = _title;
        if (title == null || !active()) {
            return;
        }
        var sub = _sub;
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = (h * 0.25).toNumber();
        var bw = (w * 0.74).toNumber();
        var bh = (sub != null) ? 50 : 32;
        var c = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cx - bw / 2 - 3, cy - bh / 2 - 3, bw + 6, bh + 6, 12);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cx - bw / 2, cy - bh / 2, bw, bh, 10);

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        if (sub != null) {
            dc.drawText(cx, cy - 10, Graphics.FONT_TINY, title, c);
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + 13, Graphics.FONT_XTINY, sub, c);
        } else {
            dc.drawText(cx, cy, Graphics.FONT_TINY, title, c);
        }
    }
}
