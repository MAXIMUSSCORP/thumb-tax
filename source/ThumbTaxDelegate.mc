// Input for the sensor test: START/ENTER re-baselines the magnetometer. BACK is left to the default (exit).
import Toybox.Lang;
import Toybox.WatchUi;

class ThumbTaxDelegate extends WatchUi.BehaviorDelegate {
    private var _view as ThumbTaxView;

    public function initialize(view as ThumbTaxView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    public function onSelect() as Boolean {
        _view.rebaseline();
        return true;
    }
}
