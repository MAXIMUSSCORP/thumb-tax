// Trend pages: what scrolling costs over a day or a week, drawn from Thumb Tax's own ledger.
// Each page has the same frame: icon + title, WEEK/TODAY pill, headline number, chart, axis, insight line.
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

module Trends {
    const RED = 0xFF5555;
    const NIGHT = 0x5555FF;
    const GREEN = 0x55FF55;
    const BAND = 0x550000;
    const HR = 0xFF0000;
    const SPO2 = 0x55AAFF;
    const GOLD = 0xFFAA00;

    // ---- Pages ----

    function scrollTax(dc as Dc, off as Number, weekly as Boolean) as Void {
        frame(dc, off, "SCROLL TAX", RED, :phone, weekly, true);
        var b = box(dc, off);
        if (weekly) {
            var taxed = Ledger.weekTaxed();
            var pct = Math.round((taxed - Ledger.LAST_WEEK_TAXED) * 100.0 / Ledger.LAST_WEEK_TAXED).toNumber();
            headline(dc, off, "-" + Ledger.fmtMin(taxed), RED,
                (pct <= 0 ? "down " + (-pct) : "up " + pct) + "% vs last week");
            var hi = 0;
            for (var i = 0; i < 7; i++) {
                var s = Ledger.WEEK_DAY_MIN[i] + Ledger.WEEK_NIGHT_MIN[i];
                if (s > hi) { hi = s; }
            }
            Chart.bars(dc, b[0], b[1], b[2], b[3], Ledger.WEEK_DAY_MIN, fill(7, RED),
                Ledger.WEEK_NIGHT_MIN, NIGHT, 0.0, hi.toFloat(), 6);
            Chart.slotLabels(dc, b[0], axisY(dc, off), b[2], Ledger.weekLabels(), 6);
        } else {
            headline(dc, off, "-" + Ledger.fmtMin(Ledger.todayTaxed()), RED, "taxed so far today");
            var colors = [] as Array<Number>;
            for (var h = 0; h < 24; h++) {
                colors.add(Ledger.isNightHour(h) ? NIGHT : RED);
            }
            Chart.bars(dc, b[0], b[1], b[2], b[3], Ledger.TODAY_HOURLY_MIN, colors, null, 0,
                0.0, Chart.maxOf(Ledger.TODAY_HOURLY_MIN).toFloat(), -1);
            Chart.tickLabels(dc, b[0], axisY(dc, off), b[2], ["0", "6", "12", "18", "24"]);
        }
        legend(dc, off, RED, "day", NIGHT, "night x2");
    }

    function sleepDebt(dc as Dc, off as Number, weekly as Boolean) as Void {
        frame(dc, off, "SLEEP DEBT", NIGHT, :moon, weekly, true);
        var b = box(dc, off);
        if (weekly) {
            var total = Ledger.sum(Ledger.WEEK_NIGHT_MIN);
            headline(dc, off, "-" + Ledger.fmtMin(total), NIGHT, "sleep withdrawn this week");
            var worst = 0;
            for (var i = 1; i < 7; i++) {
                if (Ledger.WEEK_NIGHT_MIN[i] > Ledger.WEEK_NIGHT_MIN[worst]) { worst = i; }
            }
            Chart.bars(dc, b[0], b[1], b[2], b[3], Ledger.WEEK_NIGHT_MIN, fill(7, NIGHT), null, 0,
                0.0, Chart.maxOf(Ledger.WEEK_NIGHT_MIN).toFloat(), 6);
            Chart.ref(dc, b[0], b[1], b[2], b[3], Ledger.SCROLL_NIGHT_MIN.toFloat(), 0.0,
                Chart.maxOf(Ledger.WEEK_NIGHT_MIN).toFloat());
            Chart.slotLabels(dc, b[0], axisY(dc, off), b[2], Ledger.weekLabels(), 6);
            insight(dc, off, "worst: " + Ledger.dayName(worst) + " night, " + Ledger.WEEK_NIGHT_MIN[worst] + " min");
        } else {
            var bins = Ledger.LAST_NIGHT_BINS;
            headline(dc, off, "-" + Ledger.fmtMin(Ledger.sum(bins)), NIGHT, "lost last night");
            Chart.bars(dc, b[0], b[1], b[2], b[3], bins, fill(bins.size(), NIGHT), null, 0,
                0.0, Chart.maxOf(bins).toFloat(), -1);
            Chart.tickLabels(dc, b[0], axisY(dc, off), b[2], ["8p", "11p", "2a", "5a", "8a"]);
            var first = -1;
            var last = -1;
            for (var i = 0; i < bins.size(); i++) {
                if (bins[i] > 0) {
                    if (first < 0) { first = i; }
                    last = i;
                }
            }
            if (first >= 0) {
                insight(dc, off, "scrolled " + clock(Ledger.LAST_NIGHT_START_HOUR + first) + " to "
                    + clock(Ledger.LAST_NIGHT_START_HOUR + last + 1));
            } else {
                insight(dc, off, "clean night");
            }
        }
    }

    function cardio(dc as Dc, off as Number, weekly as Boolean, cd as CardioDay) as Void {
        frame(dc, off, "CARDIO", HR, :heart, weekly, weekly || cd.demo);
        var b = box(dc, off);
        if (weekly) {
            var lifts = Ledger.WEEK_HR_LIFT;
            var avg = Math.round(Ledger.sum(lifts).toFloat() / lifts.size()).toNumber();
            headline(dc, off, "+" + avg + " bpm", HR, "avg lift while scrolling");
            Chart.bars(dc, b[0], b[1], b[2], b[3], lifts, fill(7, HR), null, 0,
                0.0, Chart.maxOf(lifts).toFloat(), 6);
            Chart.slotLabels(dc, b[0], axisY(dc, off), b[2], Ledger.weekLabels(), 6);
            insight(dc, off, "higher = harder to wind down");
        } else {
            var lift = cd.lift();
            headline(dc, off, (lift != null) ? ((lift >= 0 ? "+" : "") + lift + " bpm") : "--", HR,
                "while scrolling today");
            var r = cd.range();
            Chart.bands(dc, b[0], b[1], b[2], b[3], Ledger.TODAY_SESSIONS, 1440, BAND);
            Chart.baseline(dc, b[0], b[1] + b[3], b[2]);
            var rest = cd.restAvg;
            if (rest != null) {
                Chart.ref(dc, b[0], b[1], b[2], b[3], rest, r[0], r[1]);
            }
            Chart.line(dc, b[0], b[1], b[2], b[3], cd.bins, HR, r[0], r[1]);
            Chart.tickLabels(dc, b[0], axisY(dc, off), b[2], ["0", "6", "12", "18", "24"]);
            var s = cd.scrollAvg;
            insight(dc, off, "rest " + fmt(rest) + "  scrolling " + fmt(s));
        }
    }

    function taxReturns(dc as Dc, off as Number, weekly as Boolean) as Void {
        frame(dc, off, "TAX RETURNS", GREEN, :coin, weekly, true);
        var b = box(dc, off);
        if (weekly) {
            var earned = Ledger.sum(Ledger.WEEK_EARNED_MIN);
            var taxed = [] as Array<Number>;
            for (var i = 0; i < 7; i++) {
                taxed.add(Ledger.taxedOn(i));
            }
            headline(dc, off, "+" + Ledger.fmtMin(earned), GREEN, "earned back this week");
            Chart.pairs(dc, b[0], b[1], b[2], b[3], Ledger.WEEK_EARNED_MIN, GREEN, taxed, RED,
                Chart.maxOf(taxed).toFloat(), 6);
            Chart.slotLabels(dc, b[0], axisY(dc, off), b[2], Ledger.weekLabels(), 6);
            var net = earned - Ledger.weekTaxed();
            legend(dc, off, GREEN, "earned", RED, "net " + (net >= 0 ? "+" : "-") + Ledger.fmtMin(net));
        } else {
            var hourly = Ledger.TODAY_EARNED_HOURLY;
            headline(dc, off, "+" + Ledger.fmtMin(Ledger.sum(hourly)), GREEN, "earned today");
            Chart.bars(dc, b[0], b[1], b[2], b[3], hourly, fill(24, GREEN), null, 0,
                0.0, Chart.maxOf(hourly).toFloat(), -1);
            Chart.tickLabels(dc, b[0], axisY(dc, off), b[2], ["0", "6", "12", "18", "24"]);
            insight(dc, off, "1k steps = +5 min scroll");
        }
    }

    // Week only: overnight SpO2, scroll nights against clean nights.
    function pulseOx(dc as Dc, off as Number) as Void {
        frame(dc, off, "PULSE OX", SPO2, :drop, true, true);
        var b = box(dc, off);
        var spo2 = Ledger.WEEK_SPO2;
        var colors = [] as Array<Number>;
        var sSum = 0;
        var sN = 0;
        var cSum = 0;
        var cN = 0;
        for (var i = 0; i < 7; i++) {
            var scrolled = Ledger.WEEK_NIGHT_MIN[i] > Ledger.SCROLL_NIGHT_MIN;
            colors.add(scrolled ? RED : SPO2);
            if (scrolled) {
                sSum += spo2[i];
                sN += 1;
            } else {
                cSum += spo2[i];
                cN += 1;
            }
        }
        var sAvg = (sN > 0) ? Math.round(sSum.toFloat() / sN).toNumber() : null;
        var cAvg = (cN > 0) ? Math.round(cSum.toFloat() / cN).toNumber() : null;
        var diff = (sAvg != null && cAvg != null) ? sAvg - cAvg : null;
        headline(dc, off, (diff != null) ? ((diff > 0 ? "+" : "") + diff + "%") : "--", SPO2,
            "scroll nights vs clean");
        Chart.bars(dc, b[0], b[1], b[2], b[3], spo2, colors, null, 0, 88.0, 100.0, 6);
        Chart.slotLabels(dc, b[0], axisY(dc, off), b[2], Ledger.weekLabels(), 6);
        legend(dc, off, RED, "scroll " + fmt(sAvg) + "%", SPO2, "clean " + fmt(cAvg) + "%");
    }

    // ---- Frame pieces ----

    function frame(dc as Dc, off as Number, title as String, color as Number, icon as Symbol, weekly as Boolean, demo as Boolean) as Void {
        var cx = dc.getWidth() / 2;
        var h = dc.getHeight();
        var c = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        var y = off + (h * 0.13).toNumber();
        var tw = dc.getTextWidthInPixels(title, Graphics.FONT_XTINY);
        var ix = cx - tw / 2 - 12;
        if (icon == :phone) {
            Icons.phone(dc, ix, y, 8, color);
        } else if (icon == :moon) {
            Icons.moon(dc, ix, y, 8, color);
        } else if (icon == :heart) {
            Icons.heart(dc, ix, y, 8, color);
        } else if (icon == :coin) {
            Icons.coin(dc, ix, y, 8, GOLD);
        } else {
            Icons.drop(dc, ix, y, 8, color);
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + 6, y, Graphics.FONT_XTINY, title, c);

        // Mode pill.
        var mode = weekly ? "WEEK" : "TODAY";
        if (demo && Ledger.DEMO) {
            mode += " · demo";
        }
        var py = off + (h * 0.215).toNumber();
        var pw = dc.getTextWidthInPixels(mode, Graphics.FONT_XTINY) + 14;
        var ph = dc.getFontHeight(Graphics.FONT_XTINY);
        dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawRoundedRectangle(cx - pw / 2, py - ph / 2, pw, ph, ph / 2);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, py, Graphics.FONT_XTINY, mode, c);
    }

    function headline(dc as Dc, off as Number, value as String, color as Number, caption as String) as Void {
        var cx = dc.getWidth() / 2;
        var h = dc.getHeight();
        var c = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, off + (h * 0.31).toNumber(), Graphics.FONT_MEDIUM, value, c);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, off + (h * 0.39).toNumber(), Graphics.FONT_XTINY, caption, c);
    }

    // Chart box as [x, y, w, h].
    function box(dc as Dc, off as Number) as Array<Number> {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var bw = (w * 0.68).toNumber();
        return [w / 2 - bw / 2, off + (h * 0.45).toNumber(), bw, (h * 0.24).toNumber()];
    }

    function axisY(dc as Dc, off as Number) as Number {
        return off + (dc.getHeight() * 0.755).toNumber();
    }

    function insight(dc as Dc, off as Number, text as String) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, off + (dc.getHeight() * 0.84).toNumber(), Graphics.FONT_XTINY, text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Two colour swatches with labels, centred on the insight line.
    function legend(dc as Dc, off as Number, c1 as Number, l1 as String, c2 as Number, l2 as String) as Void {
        var cx = dc.getWidth() / 2;
        var y = off + (dc.getHeight() * 0.84).toNumber();
        var f = Graphics.FONT_XTINY;
        var gap = 12;
        var w1 = 10 + dc.getTextWidthInPixels(l1, f);
        var w2 = 10 + dc.getTextWidthInPixels(l2, f);
        var x = cx - (w1 + gap + w2) / 2;
        var lj = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(c1, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x, y - 3, 7, 7);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + 10, y, f, l1, lj);
        x += w1 + gap;
        dc.setColor(c2, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x, y - 3, 7, 7);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + 10, y, f, l2, lj);
    }

    function fill(n as Number, color as Number) as Array<Number> {
        var a = [] as Array<Number>;
        for (var i = 0; i < n; i++) {
            a.add(color);
        }
        return a;
    }

    // 24h hour -> "10pm".
    function clock(hour as Number) as String {
        var h = hour % 24;
        var suffix = (h < 12) ? "am" : "pm";
        var h12 = h % 12;
        return ((h12 == 0) ? 12 : h12) + suffix;
    }

    function fmt(v as Numeric or Null) as String {
        return (v != null) ? Math.round(v).toNumber().toString() : "--";
    }
}
