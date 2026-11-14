// Live sensor readout used to check, on the real watch, whether a nearby phone shifts the magnetometer.
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Sensor;
import Toybox.WatchUi;

class ThumbTaxView extends WatchUi.View {
    // Magnetometer units as returned by Sensor.Info.mag; tune on the watch.
    private const PHONE_DELTA = 40;

    private var _mag as Float or Null = null;
    private var _base as Float or Null = null;
    private var _accel as Array<Number> or Null = null;
    private var _hr as Number or Null = null;
    private var _temp as Float or Null = null;

    public function initialize() {
        View.initialize();
    }

    public function onShow() as Void {
        Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE, Sensor.SENSOR_TEMPERATURE]);
        Sensor.enableSensorEvents(method(:onSensor));
    }

    public function onHide() as Void {
        Sensor.enableSensorEvents(null);
        Sensor.setEnabledSensors([]);
    }

    public function rebaseline() as Void {
        _base = _mag;
        WatchUi.requestUpdate();
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
        WatchUi.requestUpdate();
    }

    public function onUpdate(dc as Dc) as Void {
        var mag = _mag;
        var base = _base;
        var delta = (mag != null && base != null) ? (mag - base) : null;
        var phone = delta != null && delta.abs() > PHONE_DELTA;

        var fg = phone ? Graphics.COLOR_BLACK : Graphics.COLOR_WHITE;
        var bg = phone ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
        dc.setColor(fg, bg);
        dc.clear();

        var cx = dc.getWidth() / 2;
        var c = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.drawText(cx, 32, Graphics.FONT_XTINY, "THUMB TAX", c);
        dc.drawText(cx, 58, Graphics.FONT_TINY, "MAG " + fmt(mag), c);
        dc.drawText(cx, 82, Graphics.FONT_TINY, "BASE " + fmt(base), c);

        var d = "--";
        if (delta != null) {
            var di = Math.round(delta).toNumber();
            d = "DELTA " + (di > 0 ? "+" : "") + di;
        }
        dc.drawText(cx, 122, Graphics.FONT_MEDIUM, d, c);

        if (phone) {
            dc.drawText(cx, 160, Graphics.FONT_SMALL, "PHONE?", c);
        }

        var a = _accel;
        var acc = "--";
        if (a != null && a.size() >= 3) {
            acc = a[0] + " " + a[1] + " " + a[2];
        }
        dc.drawText(cx, 192, Graphics.FONT_XTINY, "ACC " + acc, c);

        var hr = _hr;
        var t = _temp;
        var hrText = (hr != null) ? hr.toString() : "--";
        var tText = (t != null) ? t.format("%.1f") : "--";
        dc.drawText(cx, 216, Graphics.FONT_XTINY, "HR " + hrText + "  TEMP " + tText, c);
    }

    private function fmt(v as Float or Null) as String {
        return (v != null) ? Math.round(v).toNumber().toString() : "--";
    }
}
