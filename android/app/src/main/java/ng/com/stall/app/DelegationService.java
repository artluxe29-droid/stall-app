package ng.com.stall.app;

import com.google.androidbrowserhelper.locationdelegation.LocationDelegationExtraCommandHandler;

/**
 * Lets the web app show Android notifications (new orders, messages, deliveries)
 * and use the phone's location for live delivery tracking.
 */
public class DelegationService extends com.google.androidbrowserhelper.trusted.DelegationService {
    @Override
    public void onCreate() {
        super.onCreate();
        registerExtraCommandHandler(new LocationDelegationExtraCommandHandler());
    }
}
