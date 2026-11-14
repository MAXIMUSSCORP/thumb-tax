// Thumb mascot that reacts to the tax state: rewarded, clear, taxed by day, or taxed out of sleep.
// Drawn from primitives so it scales to any size and needs no bitmaps.
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

module Avatar {
    enum Mood {
        MOOD_REWARD,
        MOOD_CLEAR,
        MOOD_TAXED,
        MOOD_SLEEP_DEBT
    }

    // fenix 7 Pro is a 64-colour MIP screen, so every channel is 00, 55, AA or FF.
    const SKIN = 0xFFAA55;
    const SKIN_EDGE = 0xAA5500;
    const NAIL = 0xFFFFAA;
    const CHEEK = 0xFF55AA;
    const INK = 0x000000;
    const GOLD = 0xFFAA00;
    const RED = 0xFF0000;
    const SWEAT = 0x55AAFF;
    const NIGHT = 0x0055AA;
    const WHITE = 0xFFFFFF;

    // Draws the mascot centred on (cx, cy). s is the body height in pixels; tick drives the animation.
    function draw(dc as Dc, cx as Number, cy as Number, s as Number, mood as Mood, tick as Number) as Void {
        var w = (s * 0.6).toNumber();
        var dx = 0;
        var dy = 0;
        if (mood == MOOD_REWARD) {
            dy = -(Math.sin(tick * 0.6).abs() * s * 0.08).toNumber();
        } else if (mood == MOOD_TAXED) {
            dx = (tick % 10 < 4) ? ((tick % 2 == 0) ? 3 : -3) : 0;
        } else if (mood == MOOD_SLEEP_DEBT) {
            dy = (Math.sin(tick * 0.15) * s * 0.03).toNumber();
        } else {
            dy = (Math.sin(tick * 0.3) * s * 0.02).toNumber();
        }

        var x = cx + dx;
        var top = cy - s / 2 + dy;

        drawBody(dc, x, top, w, s);

        var ey = top + (s * 0.5).toNumber();
        var ex = (w * 0.2).toNumber();
        var er = (s * 0.045).toNumber();
        if (er < 3) {
            er = 3;
        }
        var my = top + (s * 0.68).toNumber();
        var mr = (s * 0.1).toNumber();

        if (mood == MOOD_REWARD) {
            drawReward(dc, x, top, w, s, ex, ey, er, my, mr, tick);
        } else if (mood == MOOD_TAXED) {
            drawTaxed(dc, x, top, w, s, ex, ey, er, my, mr, tick);
        } else if (mood == MOOD_SLEEP_DEBT) {
            drawSleepDebt(dc, x, top, w, s, ex, ey, er, my, mr, tick);
        } else {
            drawClear(dc, x, ex, ey, er, my, mr, tick);
        }
        dc.setPenWidth(1);
    }

    function drawBody(dc as Dc, x as Number, top as Number, w as Number, s as Number) as Void {
        var left = x - w / 2;
        dc.setColor(SKIN, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(left, top, w, s, w / 2);
        dc.setPenWidth(3);
        dc.setColor(SKIN_EDGE, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(left, top, w, s, w / 2);

        // Thumbnail.
        var nw = (w * 0.64).toNumber();
        var nh = (s * 0.3).toNumber();
        var nt = top + (s * 0.07).toNumber();
        dc.setColor(NAIL, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x - nw / 2, nt, nw, nh, nw / 3);
        dc.setPenWidth(2);
        dc.setColor(SKIN_EDGE, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(x - nw / 2, nt, nw, nh, nw / 3);

        // Knuckle creases.
        var k = top + (s * 0.85).toNumber();
        var k1 = (w * 0.18).toNumber();
        var k2 = (w * 0.11).toNumber();
        dc.drawLine(x - k1, k, x + k1, k);
        dc.drawLine(x - k2, k + (s * 0.05).toNumber(), x + k2, k + (s * 0.05).toNumber());
    }

    // Tax return: squinting grin, cheeks, a gold coin floating up and sparkles.
    function drawReward(dc as Dc, x as Number, top as Number, w as Number, s as Number,
            ex as Number, ey as Number, er as Number, my as Number, mr as Number, tick as Number) as Void {
        dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawArc(x - ex, ey + er, er + 2, Graphics.ARC_COUNTER_CLOCKWISE, 20, 160);
        dc.drawArc(x + ex, ey + er, er + 2, Graphics.ARC_COUNTER_CLOCKWISE, 20, 160);

        // Open grin: a full circle with its top half painted back to skin.
        dc.fillCircle(x, my - mr / 3, mr);
        dc.setColor(SKIN, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x - mr - 1, my - mr / 3 - mr - 1, mr * 2 + 2, mr + 1);

        dc.setColor(CHEEK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - (w * 0.32).toNumber(), my - (s * 0.06).toNumber(), er);
        dc.fillCircle(x + (w * 0.32).toNumber(), my - (s * 0.06).toNumber(), er);

        var rise = (tick % 20) * 2;
        coin(dc, x + w / 2 + 20, top + 30 - rise, 12, GOLD, "+");

        if ((tick / 3) % 2 == 0) {
            sparkle(dc, x - w / 2 - 18, top + 18, 6);
            sparkle(dc, x + w / 2 + 14, top + (s * 0.65).toNumber(), 5);
        } else {
            sparkle(dc, x - w / 2 - 12, top + (s * 0.55).toNumber(), 5);
        }
    }

    // All clear: calm open eyes, small smile, occasional blink.
    function drawClear(dc as Dc, x as Number, ex as Number, ey as Number, er as Number,
            my as Number, mr as Number, tick as Number) as Void {
        dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
        if (tick % 30 < 2) {
            dc.setPenWidth(3);
            dc.drawLine(x - ex - er, ey, x - ex + er, ey);
            dc.drawLine(x + ex - er, ey, x + ex + er, ey);
        } else {
            dc.fillCircle(x - ex, ey, er);
            dc.fillCircle(x + ex, ey, er);
            dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x - ex + 1, ey - 1, 1);
            dc.fillCircle(x + ex + 1, ey - 1, 1);
        }
        dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawArc(x, my - mr, mr, Graphics.ARC_COUNTER_CLOCKWISE, 215, 325);
    }

    // Day tax: worried brows, frown, sweat drop, and a red coin falling away.
    function drawTaxed(dc as Dc, x as Number, top as Number, w as Number, s as Number,
            ex as Number, ey as Number, er as Number, my as Number, mr as Number, tick as Number) as Void {
        dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - ex, ey, er);
        dc.fillCircle(x + ex, ey, er);
        dc.setPenWidth(3);
        // Inner ends raised reads as worry.
        dc.drawLine(x - ex - er * 2, ey - er * 2, x - ex + er * 2, ey - er * 3 - 2);
        dc.drawLine(x + ex + er * 2, ey - er * 2, x + ex - er * 2, ey - er * 3 - 2);
        dc.drawArc(x, my + mr, mr, Graphics.ARC_COUNTER_CLOCKWISE, 35, 145);

        // Sweat drop sliding down the side.
        var sx = x + w / 2 - 4;
        var sy = top + (s * 0.3).toNumber() + (tick % 12);
        dc.setColor(SWEAT, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(sx, sy, 5);
        dc.fillPolygon([[sx - 5, sy], [sx + 5, sy], [sx, sy - 11]]);

        var fall = (tick % 20) * 2;
        coin(dc, x - w / 2 - 22, top + (s * 0.35).toNumber() + fall, 12, RED, "-");
    }

    // Sleep tax: nightcap, heavy lids with bags, a yawn, and drifting Zs.
    function drawSleepDebt(dc as Dc, x as Number, top as Number, w as Number, s as Number,
            ex as Number, ey as Number, er as Number, my as Number, mr as Number, tick as Number) as Void {
        dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawLine(x - ex - er - 1, ey, x - ex + er + 1, ey);
        dc.drawLine(x + ex - er - 1, ey, x + ex + er + 1, ey);
        dc.drawArc(x - ex, ey, er, Graphics.ARC_COUNTER_CLOCKWISE, 200, 340);
        dc.drawArc(x + ex, ey, er, Graphics.ARC_COUNTER_CLOCKWISE, 200, 340);

        dc.setColor(NIGHT, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawArc(x - ex, ey + er + 2, er, Graphics.ARC_COUNTER_CLOCKWISE, 210, 330);
        dc.drawArc(x + ex, ey + er + 2, er, Graphics.ARC_COUNTER_CLOCKWISE, 210, 330);

        dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
        var yawn = (tick % 40 < 20) ? mr / 2 : mr / 3;
        dc.fillEllipse(x, my, mr / 2, yawn);

        // Nightcap over the nail, tipped to one side.
        var bl = [x - (w * 0.5).toNumber(), top + (w * 0.3).toNumber()];
        var br = [x + (w * 0.5).toNumber(), top + (w * 0.2).toNumber()];
        var tip = [x + (w * 0.62).toNumber(), top - (s * 0.26).toNumber()];
        dc.setColor(NIGHT, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([bl, br, tip]);
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(5);
        dc.drawLine(bl[0], bl[1], br[0], br[1]);
        dc.fillCircle(tip[0], tip[1], 6);

        var drift = (tick / 2) % 12;
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        var j = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.drawText(x - w / 2 - 16, top + (s * 0.35).toNumber() - drift, Graphics.FONT_XTINY, "z", j);
        dc.drawText(x - w / 2 - 28, top + (s * 0.12).toNumber() - drift, Graphics.FONT_SMALL, "Z", j);
    }

    function coin(dc as Dc, x as Number, y as Number, r as Number, color as Number, sign as String) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, r);
        dc.setPenWidth(2);
        dc.setColor(SKIN_EDGE, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(x, y, r);
        dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_XTINY, sign, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    function sparkle(dc as Dc, x as Number, y as Number, r as Number) as Void {
        dc.setColor(GOLD, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(x - r, y, x + r, y);
        dc.drawLine(x, y - r, x, y + r);
    }
}
