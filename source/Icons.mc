// Small sensor icons drawn from primitives, centred on (x, y) and roughly 2r across.
import Toybox.Graphics;
import Toybox.Lang;

module Icons {
    // Heart rate.
    function heart(dc as Dc, x as Number, y as Number, r as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var h = r / 2;
        dc.fillCircle(x - h, y - r / 4, h);
        dc.fillCircle(x + h, y - r / 4, h);
        dc.fillPolygon([[x - r, y - r / 8], [x + r, y - r / 8], [x, y + r]]);
    }

    // Temperature.
    function thermometer(dc as Dc, x as Number, y as Number, r as Number, color as Number) as Void {
        var sw = (r * 0.6).toNumber();
        var bulb = (r * 0.45).toNumber();
        var by = y + (r * 0.55).toNumber();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawRoundedRectangle(x - sw / 2, y - r, sw, (r * 1.5).toNumber(), sw / 2);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x - sw / 4, y - r / 4, sw / 2, by - (y - r / 4));
        dc.fillCircle(x, by, bulb);
        dc.setPenWidth(1);
    }

    // Movement (accelerometer): four-way arrows.
    function motion(dc as Dc, x as Number, y as Number, r as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        var a = r - 3;
        dc.drawLine(x - a, y, x + a, y);
        dc.drawLine(x, y - a, x, y + a);
        var t = (r * 0.4).toNumber();
        dc.fillPolygon([[x - r, y], [x - r + t, y - t], [x - r + t, y + t]]);
        dc.fillPolygon([[x + r, y], [x + r - t, y - t], [x + r - t, y + t]]);
        dc.fillPolygon([[x, y - r], [x - t, y - r + t], [x + t, y - r + t]]);
        dc.fillPolygon([[x, y + r], [x - t, y + r - t], [x + t, y + r - t]]);
        dc.setPenWidth(1);
    }

    // Blood oxygen: a drop.
    function drop(dc as Dc, x as Number, y as Number, r as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var br = (r * 0.62).toNumber();
        var cy = y + (r * 0.3).toNumber();
        dc.fillCircle(x, cy, br);
        dc.fillPolygon([[x - br, cy - 1], [x + br, cy - 1], [x, y - r]]);
    }

    // Scroll tax: a phone outline with a screen.
    function phone(dc as Dc, x as Number, y as Number, r as Number, color as Number) as Void {
        var w = (r * 1.1).toNumber();
        var h = r * 2;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x - w / 2, y - r, w, h, 3);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x - w / 2 + 2, y - r + 3, w - 4, h - 7);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x - w / 2 + 4, y - r + 6, w - 8, 2);
        dc.fillRectangle(x - w / 2 + 4, y - r + 10, w - 8, 2);
    }

    // Sleep: crescent moon (cut out against a black background).
    function moon(dc as Dc, x as Number, y as Number, r as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, r);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x + r / 2, y - r / 3, (r * 0.85).toNumber());
    }

    // Tax returns: a coin with a plus.
    function coin(dc as Dc, x as Number, y as Number, r as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, r);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        var a = r / 2;
        dc.drawLine(x - a, y, x + a, y);
        dc.drawLine(x, y - a, x, y + a);
        dc.setPenWidth(1);
    }

    // Magnetometer: horseshoe magnet with pale tips.
    function magnet(dc as Dc, x as Number, y as Number, r as Number, color as Number) as Void {
        // Tilted horseshoe: legs point up-right, with white pole tips.
        var pen = (r * 0.45).toNumber();
        var arcR = (r * 0.55).toNumber();
        var legTop = y - r;
        var tip = (r * 0.4).toNumber();
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(pen);
        dc.drawArc(x, y, arcR, Graphics.ARC_COUNTER_CLOCKWISE, 180, 360);
        dc.fillRectangle(x - arcR - pen / 2, legTop + tip, pen, y - legTop - tip + 1);
        dc.fillRectangle(x + arcR - pen / 2, legTop + tip, pen, y - legTop - tip + 1);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x - arcR - pen / 2, legTop, pen, tip);
        dc.fillRectangle(x + arcR - pen / 2, legTop, pen, tip);
        // Field lines between the poles.
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(x - arcR / 2, legTop - 2, x + arcR / 2, legTop - 2);
        dc.drawLine(x - arcR / 3, legTop - 5, x + arcR / 3, legTop - 5);
    }
}
