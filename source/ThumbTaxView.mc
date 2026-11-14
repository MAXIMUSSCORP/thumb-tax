// Sensor screen. Page 0 is the live summary (is a phone in hand right now?).
// Pages 1-5 are trends from Thumb Tax's own ledger: scroll tax, sleep debt, cardio, tax returns, pulse ox.
// START re-baselines on page 0 and toggles WEEK / TODAY on the trend pages.
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Sensor;
import Toybox.Timer;
import Toybox.WatchUi;

class ThumbTaxView extends WatchUi.View {
    // Magnetometer units as returned by Sensor.Info.mag; tune on the watch.
    private const PHONE_DELTA = 40;
    private const PAGES = 6;

    private const COLOR_OK = 0x55FF55;
    private const COLOR_ALERT = 0xFF5555;

    private var _mag as Float or Null = null;
    private var _base as Float or Null = null;
    private var _accel as Array<Number> or Null = null;
    private var _hr as Number or Null = null;
    private var _temp as Float or Null = null;
    private var _spo2 as Number or Null = null;

    private var _cardio as CardioDay = new CardioDay();
    private var _weekly as Boolean = true;

    // Scrolling: _page is the target, _scroll eases towards it.
    private var _page as Number = 0;
    private var _scroll as Float = 0.0;
    private var _anim as Timer.Timer or Null = null;

    public function initialize() {
        View.initialize();
    }

    public function onShow() as Void {
        Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE, Sensor.SENSOR_TEMPERATURE, Sensor.SENSOR_PULSE_OXIMETRY]);
        Sensor.enableSensorEvents(method(:onSensor));
        _cardio.load();
    }

    public function onHide() as Void {
        Sensor.enableSensorEvents(null);
        Sensor.setEnabledSensors([]);
        stopAnim();
    }

    // START: re-baseline on the summary, switch WEEK / TODAY on trend pages.
    public function select() as Void {
        if (_page == 0) {
            _base = _mag;
        } else {
            _weekly = !_weekly;
            if (!_weekly) {
                _cardio.load();
            }
        }
        WatchUi.requestUpdate();
    }

    // Moves one page up or down; returns false at either end.
    public function scroll(step as Number) as Boolean {
        var next = _page + step;
        if (next < 0 || next >= PAGES) {
            return false;
        }
        _page = next;
        if (_anim == null) {
            var t = new Timer.Timer();
            // 50 ms is the shortest timer Connect IQ allows.
            t.start(method(:onAnim), 50, true);
            _anim = t;
        }
        return true;
    }

    public function onAnim() as Void {
        var diff = _page - _scroll;
        if (diff.abs() < 0.02) {
            _scroll = _page.toFloat();
            stopAnim();
        } else {
            _scroll += diff * 0.5;
        }
        WatchUi.requestUpdate();
    }

    private function stopAnim() as Void {
        var t = _anim;
        if (t != null) {
            t.stop();
        }
        _anim = null;
    }

    public function onSensor(info as Sensor.Info) as Void {
        var m = info.mag;
        if (m != null && m.size() >= 3) {
            var x = m[0] as Numeric;
            var y = m[1] as Numeric;
            var z = m[2] as Numeric;
            _mag = Math.sqrt(x * x + y * y + z * z).toFloat();
            if (_base == null) {
                _base = _mag;
            }
        }
        _accel = info.accel;
        _hr = info.heartRate;
        _temp = info.temperature;
        _spo2 = info.oxygenSaturation;
        // Trend pages are static between toggles; only redraw when the live summary is on screen.
        if (_scroll < 1.0) {
            WatchUi.requestUpdate();
        }
    }

    private function delta() as Float or Null {
        var mag = _mag;
        var base = _base;
        return (mag != null && base != null) ? (mag - base) : null;
    }

    private function gForce() as Float or Null {
        var a = _accel;
        if (a == null || a.size() < 3) {
            return null;
        }
        var ax = a[0].toFloat();
        var ay = a[1].toFloat();
        var az = a[2].toFloat();
        return (Math.sqrt(ax * ax + ay * ay + az * az) / 1000.0).toFloat();
    }

    public function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var h = dc.getHeight();
        var p0 = Math.floor(_scroll).toNumber();
        for (var p = p0; p <= p0 + 1 && p < PAGES; p++) {
            var off = ((p - _scroll) * h).toNumber();
            if (off > -h && off < h) {
                drawPage(dc, p, off);
            }
        }
        drawScrollbar(dc);
    }

    private function drawPage(dc as Dc, p as Number, off as Number) as Void {
        if (p == 0) {
            drawSummary(dc, off);
        } else if (p == 1) {
            Trends.scrollTax(dc, off, _weekly);
        } else if (p == 2) {
            Trends.sleepDebt(dc, off, _weekly);
        } else if (p == 3) {
            Trends.cardio(dc, off, _weekly, _cardio);
        } else if (p == 4) {
            Trends.taxReturns(dc, off, _weekly);
        } else {
            Trends.pulseOx(dc, off);
        }
        if (p < PAGES - 1) {
            drawChevron(dc, dc.getWidth() / 2, off + (dc.getHeight() * 0.94).toNumber());
        }
    }

    // ---- Page 0: live summary ----

    private function drawSummary(dc as Dc, off as Number) as Void {
        var mag = _mag;
        var base = _base;
        var d = delta();
        var phone = d != null && d.abs() > PHONE_DELTA;

        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var c = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var accent = phone ? COLOR_ALERT : COLOR_OK;

        drawGauge(dc, cx, h / 2 + off, w / 2 - 6, d, accent);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, off + (h * 0.13).toNumber(), Graphics.FONT_XTINY, "THUMB TAX", c);

        var sy = off + (h * 0.24).toNumber();
        var status = (d == null) ? "WAITING" : (phone ? "PHONE?" : "NO PHONE");
        var sw = dc.getTextWidthInPixels(status, Graphics.FONT_XTINY);
        Icons.magnet(dc, cx - sw / 2 - 10, sy + 1, 10, accent);
        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + 8, sy, Graphics.FONT_XTINY, status, c);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, off + (h * 0.40).toNumber(), Graphics.FONT_NUMBER_MEDIUM, signed(d), c);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, off + (h * 0.53).toNumber(), Graphics.FONT_XTINY, "field " + fmt(mag) + " / base " + fmt(base), c);

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx - 80, off + (h * 0.595).toNumber(), cx + 80, off + (h * 0.595).toNumber());

        var hr = _hr;
        var t = _temp;
        var spo2 = _spo2;
        var g = gForce();

        var iy = off + (h * 0.655).toNumber();
        var vy = off + (h * 0.74).toNumber();
        var ly = off + (h * 0.815).toNumber();
        var step = (w * 0.195).toNumber();
        var xs = [cx - step * 3 / 2, cx - step / 2, cx + step / 2, cx + step * 3 / 2] as Array<Number>;

        Icons.heart(dc, xs[0], iy, 9, 0xFF0000);
        Icons.thermometer(dc, xs[1], iy, 9, 0xFFAA00);
        Icons.motion(dc, xs[2], iy, 9, 0x55FF55);
        Icons.drop(dc, xs[3], iy, 9, 0x55AAFF);

        tile(dc, xs[0], vy, ly, (hr != null) ? hr.toString() : "--", "BPM");
        tile(dc, xs[1], vy, ly, (t != null) ? t.format("%.0f") + "°" : "--", "TEMP");
        tile(dc, xs[2], vy, ly, (g != null) ? g.format("%.1f") : "--", "G");
        tile(dc, xs[3], vy, ly, (spo2 != null) ? spo2.toString() + "%" : "--", "SPO2");
    }

    private function tile(dc as Dc, x as Number, vy as Number, ly as Number, value as String, label as String) as Void {
        var c = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, vy, Graphics.FONT_TINY, value, c);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, ly, Graphics.FONT_XTINY, label, c);
    }

    // Ring around the bezel: fills with |delta|; the threshold sits at the top tick.
    private function drawGauge(dc as Dc, cx as Number, cy as Number, r as Number, d as Float or Null, accent as Number) as Void {
        var start = 225;
        var sweep = 270;
        dc.setPenWidth(6);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, start, start - sweep);

        if (d != null) {
            var frac = d.abs() / (PHONE_DELTA * 2.0);
            if (frac > 1.0) {
                frac = 1.0;
            }
            var len = (sweep * frac).toNumber();
            if (len > 0) {
                dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, start, start - len);
            }
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawLine(cx, cy - r - 5, cx, cy - r + 6);
        dc.setPenWidth(1);
    }

    // ---- Chrome ----

    private function drawChevron(dc as Dc, x as Number, y as Number) as Void {
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(x - 6, y - 3, x, y + 3);
        dc.drawLine(x, y + 3, x + 6, y - 3);
        dc.setPenWidth(1);
    }

    // Scroll position along the right edge, inside the summary gauge ring.
    private function drawScrollbar(dc as Dc) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var r = cx - 16;
        var top = 30;
        var span = 60.0;
        var seg = span / PAGES;
        dc.setPenWidth(3);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, top, top - span);
        var s = top - seg * _scroll;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, s, s - seg);
        dc.setPenWidth(1);
    }

    private function signed(v as Numeric or Null) as String {
        if (v == null) {
            return "--";
        }
        var n = Math.round(v).toNumber();
        return (n > 0 ? "+" : "") + n;
    }

    private function fmt(v as Numeric or Null) as String {
        return (v != null) ? Math.round(v).toNumber().toString() : "--";
    }
}
