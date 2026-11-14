// Entry point for Thumb Tax; wires the live sensor test view to its input delegate.
import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class ThumbTaxApp extends Application.AppBase {

    public function initialize() {
        AppBase.initialize();
    }

    public function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new $.AvatarView();
        return [view, new $.AvatarDelegate(view)];
    }
}
