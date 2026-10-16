package ng.com.stall.app;

import android.net.Uri;

/**
 * Opens Stall full screen in a Trusted Web Activity.
 * Links into Stall (an item, an order, a collection, a payment return) open at that page;
 * everything else opens the app's home at /app.
 */
public class LauncherActivity extends com.google.androidbrowserhelper.trusted.LauncherActivity {
    @Override
    protected Uri getLaunchingUrl() {
        Uri uri = super.getLaunchingUrl();
        // A plain https://stall.com.ng/ link would show the website; inside the app we want the app itself.
        if (uri != null && getString(R.string.hostName).equals(uri.getHost())
                && (uri.getPath() == null || uri.getPath().isEmpty() || "/".equals(uri.getPath()))
                && uri.getQuery() == null) {
            return Uri.parse(getString(R.string.launchUrl));
        }
        return uri;
    }
}
