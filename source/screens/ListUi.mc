// Shared round-screen list: the focused row sits in the middle, inverted (white card, black text);
// neighbours fade above and below. Rows are dictionaries:
//   :title (String), :sub (String?), :sub2 (String?), :header (Boolean?), :disabled (Boolean?), :mark (Boolean?)
// Header rows are never focused; navigation skips them.
import Toybox.Graphics;
import Toybox.Lang;

module ListUi {
    const DIM = 0x555555;

    function isSelectable(row as Dictionary) as Boolean {
        return row[:header] != true;
    }

    // First selectable index at or after i (searching in direction dir), or -1.
    function nextSelectable(rows as Array<Dictionary>, i as Number, dir as Number) as Number {
        var j = i;
        while (j >= 0 && j < rows.size()) {
            if (isSelectable(rows[j])) {
                return j;
            }
            j += dir;
        }
        return -1;
    }

    // Moves focus one selectable row; stays put at either end.
    function move(rows as Array<Dictionary>, focus as Number, dir as Number) as Number {
        var j = nextSelectable(rows, focus + dir, dir);
        return (j < 0) ? focus : j;
    }

    function draw(dc as Dc, title as String, rows as Array<Dictionary>, focus as Number) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2 + 6;
        var c = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        if (rows.size() == 0) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy, Graphics.FONT_XTINY, "nothing here", c);
            return;
        }

        // Neighbours: two above, two below.
        var gaps = [-88, -50, 50, 88] as Array<Number>;
        var offs = [-2, -1, 1, 2] as Array<Number>;
        for (var k = 0; k < offs.size(); k++) {
            var i = focus + offs[k];
            if (i < 0 || i >= rows.size()) {
                continue;
            }
            var far = offs[k] == -2 || offs[k] == 2;
            drawNeighbour(dc, cx, cy + gaps[k], rows[i], far, (w * 0.78).toNumber());
        }

        drawFocus(dc, cx, cy, rows[focus], (w * 0.84).toNumber());

        // Title last so it sits above any neighbour that drifts up.
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(0, 0, w, (h * 0.17).toNumber());
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.11).toNumber(), Graphics.FONT_XTINY, title, c);

        drawScrollbar(dc, focus, rows.size());
    }

    function drawFocus(dc as Dc, cx as Number, cy as Number, row as Dictionary, maxW as Number) as Void {
        var c = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var disabled = row[:disabled] == true;
        var sub = row[:sub] as String?;
        var sub2 = row[:sub2] as String?;
        var lines = 1 + (sub != null ? 1 : 0) + (sub2 != null ? 1 : 0);
        var ch = 20 + lines * 16;

        dc.setColor(disabled ? Graphics.COLOR_LT_GRAY : Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cx - maxW / 2, cy - ch / 2, maxW, ch, 10);

        var title = row[:title] as String;
        var font = fit(dc, title, Graphics.FONT_TINY, maxW - 28);
        var y = cy - (lines - 1) * 9;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, font, title, c);
        if (row[:mark] == true) {
            var tw = dc.getTextWidthInPixels(title, font);
            dc.fillCircle(cx - tw / 2 - 10, y, 4);
        }
        if (sub != null) {
            y += 18;
            dc.setColor(disabled ? Graphics.COLOR_BLACK : DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y, Graphics.FONT_XTINY, sub, c);
        }
        if (sub2 != null) {
            y += 16;
            dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y, Graphics.FONT_XTINY, sub2, c);
        }
    }

    function drawNeighbour(dc as Dc, cx as Number, y as Number, row as Dictionary, far as Boolean, maxW as Number) as Void {
        var c = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var title = row[:title] as String;
        if (row[:header] == true) {
            // Group header: small caps between two rules.
            var tw = dc.getTextWidthInPixels(title, Graphics.FONT_XTINY);
            dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(cx - 70, y, cx - tw / 2 - 6, y);
            dc.drawLine(cx + tw / 2 + 6, y, cx + 70, y);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y, Graphics.FONT_XTINY, title, c);
            return;
        }
        var disabled = row[:disabled] == true;
        var color = disabled ? DIM : (far ? Graphics.COLOR_LT_GRAY : Graphics.COLOR_WHITE);
        var font = fit(dc, title, far ? Graphics.FONT_XTINY : Graphics.FONT_TINY, maxW);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, font, title, c);
        if (row[:mark] == true) {
            var tw = dc.getTextWidthInPixels(title, font);
            dc.fillCircle(cx - tw / 2 - 9, y, 3);
        }
    }

    // Falls back to the extra-tiny font when the text is too wide.
    function fit(dc as Dc, text as String, font as Graphics.FontType, maxW as Number) as Graphics.FontType {
        return (dc.getTextWidthInPixels(text, font) > maxW) ? Graphics.FONT_XTINY : font;
    }

    function drawScrollbar(dc as Dc, focus as Number, n as Number) as Void {
        if (n < 2) {
            return;
        }
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var r = cx - 6;
        var top = 30;
        var span = 60.0;
        var seg = span / n;
        if (seg < 4.0) {
            seg = 4.0;
        }
        var pos = top - (span - seg) * focus / (n - 1);
        dc.setPenWidth(3);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, top, top - span);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, pos, pos - seg);
        dc.setPenWidth(1);
    }

    // Signed bank amount: "+12 min", "-1h 05m", or seconds under a minute ("-11s").
    function signedTime(sec as Number) as String {
        var sign = (sec < 0) ? "-" : "+";
        var a = (sec < 0) ? -sec : sec;
        return sign + ((a < 60) ? a + "s" : Records.fmtMin(a / 60));
    }

    // Splits text into at most two lines that fit maxW.
    function wrap(dc as Dc, text as String, font as Graphics.FontType, maxW as Number) as Array<String> {
        if (dc.getTextWidthInPixels(text, font) <= maxW) {
            return [text];
        }
        var chars = text.toCharArray();
        var best = -1;
        for (var i = 0; i < chars.size(); i++) {
            if (chars[i] == ' ') {
                var head = text.substring(0, i) as String;
                if (dc.getTextWidthInPixels(head, font) <= maxW) {
                    best = i;
                } else {
                    break;
                }
            }
        }
        if (best < 0) {
            return [text];
        }
        return [text.substring(0, best) as String, text.substring(best + 1, text.length()) as String];
    }
}
