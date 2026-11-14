// Small chart primitives for the trend pages: bars, paired bars, a line, shaded bands and axis labels.
import Toybox.Graphics;
import Toybox.Lang;

module Chart {
    const AXIS = 0x555555;

    function scaled(v as Float, lo as Float, hi as Float, h as Number) as Number {
        var span = hi - lo;
        if (span <= 0.0) {
            return 0;
        }
        var px = ((v - lo) / span * h).toNumber();
        return (px < 0) ? 0 : ((px > h) ? h : px);
    }

    function maxOf(a as Array<Number>) as Number {
        var m = 0;
        for (var i = 0; i < a.size(); i++) {
            if (a[i] > m) {
                m = a[i];
            }
        }
        return m;
    }

    // Vertical bars, one colour per bar, optionally stacked with series b on top. mark gets an underline.
    function bars(dc as Dc, x as Number, y as Number, w as Number, h as Number,
            a as Array<Number>, colors as Array<Number>, b as Array<Number> or Null, colorB as Number,
            lo as Float, hi as Float, mark as Number) as Void {
        var n = a.size();
        var slot = w.toFloat() / n;
        var bw = (slot * 0.62).toNumber();
        if (bw < 2) {
            bw = 2;
        }
        baseline(dc, x, y + h, w);
        for (var i = 0; i < n; i++) {
            var bx = x + (slot * i + (slot - bw) / 2).toNumber();
            var ha = scaled(a[i].toFloat(), lo, hi, h);
            dc.setColor(colors[i], Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(bx, y + h - ha, bw, ha);
            if (b != null) {
                var hb = scaled(b[i].toFloat(), 0.0, hi - lo, h);
                dc.setColor(colorB, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(bx, y + h - ha - hb, bw, hb);
            }
            if (i == mark) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(bx, y + h + 2, bw, 2);
            }
        }
    }

    // Two bars per slot, side by side: a (left) and b (right), on the same scale.
    function pairs(dc as Dc, x as Number, y as Number, w as Number, h as Number,
            a as Array<Number>, colorA as Number, b as Array<Number>, colorB as Number, hi as Float, mark as Number) as Void {
        var n = a.size();
        var slot = w.toFloat() / n;
        var bw = (slot * 0.32).toNumber();
        baseline(dc, x, y + h, w);
        for (var i = 0; i < n; i++) {
            var sx = x + (slot * i + slot * 0.15).toNumber();
            var ha = scaled(a[i].toFloat(), 0.0, hi, h);
            var hb = scaled(b[i].toFloat(), 0.0, hi, h);
            dc.setColor(colorA, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(sx, y + h - ha, bw, ha);
            dc.setColor(colorB, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(sx + bw + 1, y + h - hb, bw, hb);
            if (i == mark) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(sx, y + h + 2, bw * 2 + 1, 2);
            }
        }
    }

    // Line through evenly spaced values; null values break the line.
    function line(dc as Dc, x as Number, y as Number, w as Number, h as Number,
            vals as Array<Float or Null>, color as Number, lo as Float, hi as Float) as Void {
        var n = vals.size();
        var stepX = w.toFloat() / (n - 1);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        // -1 marks "no previous point" so the line breaks over gaps.
        var px = -1;
        var py = 0;
        for (var i = 0; i < n; i++) {
            var v = vals[i];
            if (v == null) {
                px = -1;
                continue;
            }
            var cx = x + (i * stepX).toNumber();
            var cy = y + h - scaled(v, lo, hi, h);
            if (px >= 0) {
                dc.drawLine(px, py, cx, cy);
            }
            px = cx;
            py = cy;
        }
        if (px >= 0) {
            dc.fillCircle(px, py, 3);
        }
        dc.setPenWidth(1);
    }

    // Shaded vertical bands for [start, end] ranges on an axis of length total. Bands are at least 3 px wide.
    function bands(dc as Dc, x as Number, y as Number, w as Number, h as Number,
            ranges as Array<Array<Number>>, total as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < ranges.size(); i++) {
            var r = ranges[i];
            var x0 = x + (r[0] * w / total);
            var bw = (r[1] - r[0]) * w / total;
            if (bw < 3) {
                bw = 3;
            }
            dc.fillRectangle(x0, y, bw, h);
        }
    }

    // Dashed horizontal reference line at value v.
    function ref(dc as Dc, x as Number, y as Number, w as Number, h as Number, v as Float, lo as Float, hi as Float) as Void {
        var ry = y + h - scaled(v, lo, hi, h);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        for (var dx = 0; dx < w; dx += 8) {
            dc.drawLine(x + dx, ry, x + dx + 4, ry);
        }
    }

    // One label centred under each slot; the marked slot is white, the rest grey.
    function slotLabels(dc as Dc, x as Number, y as Number, w as Number, labels as Array<String>, mark as Number) as Void {
        var n = labels.size();
        var slot = w.toFloat() / n;
        for (var i = 0; i < n; i++) {
            dc.setColor((i == mark) ? Graphics.COLOR_WHITE : Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + (slot * i + slot / 2).toNumber(), y, Graphics.FONT_XTINY, labels[i],
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // Labels spread evenly from the left edge to the right edge.
    function tickLabels(dc as Dc, x as Number, y as Number, w as Number, labels as Array<String>) as Void {
        var n = labels.size();
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < n; i++) {
            dc.drawText(x + w * i / (n - 1), y, Graphics.FONT_XTINY, labels[i],
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    function baseline(dc as Dc, x as Number, y as Number, w as Number) as Void {
        dc.setPenWidth(1);
        dc.setColor(AXIS, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(x, y, x + w, y);
    }
}
