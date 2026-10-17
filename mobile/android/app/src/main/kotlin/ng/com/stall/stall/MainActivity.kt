package ng.com.stall.stall

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Stall's pushes use the "stall" channel (see fcmSend on the server). Android needs it to exist to show them with sound.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel("stall", "Orders and messages", NotificationManager.IMPORTANCE_HIGH)
            ch.description = "Order updates, payments and chat messages"
            getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
        }
    }
}
