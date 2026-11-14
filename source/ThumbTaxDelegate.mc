// Input for the sensor screen: START re-baselines (summary) or toggles WEEK/TODAY (trends), UP/DOWN scroll pages.
import Toybox.Lang;
import Toybox.WatchUi;

class ThumbTaxDelegate extends WatchUi.BehaviorDelegate {
    private var _view as ThumbTaxView;

    public function initialize(view as ThumbTaxView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    public function onSelect() as Boolean {
        _view.select();
        return true;
    }

    // DOWN / swipe up scrolls to the next detail page; UP / swipe down goes back.
    public function onNextPage() as Boolean {
        _view.scroll(1);
        return true;
    }

    public function onPreviousPage() as Boolean {
        _view.scroll(-1);
        return true;
    }
}
