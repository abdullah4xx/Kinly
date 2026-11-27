package app.kinly.chat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder

/**
 * Foreground service that keeps the Kinly process alive so the Rust node can
 * keep receiving messages while the app is in the background.
 *
 * The notification is intentionally as quiet as Android allows: minimum
 * importance, no sound, no vibration, no badge and no timestamp. Android still
 * requires a visible notification for a foreground service, so it cannot be
 * removed while background delivery is enabled.
 */
class KinlyService : Service() {
    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // A new id: importance cannot be changed after a channel exists.
            val channel = NotificationChannel(
                CHANNEL_ID,
                getString(R.string.service_channel_quiet),
                NotificationManager.IMPORTANCE_MIN,
            ).apply {
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
                description = getString(R.string.service_channel_quiet_body)
            }
            manager.createNotificationChannel(channel)
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setContentTitle(getString(R.string.service_title_quiet))
            .setContentText(getString(R.string.service_body_quiet))
            .setSmallIcon(R.drawable.ic_stat_kinly)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(Notification.CATEGORY_SERVICE)
            .apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    setPriority(Notification.PRIORITY_MIN)
                } else {
                    @Suppress("DEPRECATION")
                    setPriority(Notification.PRIORITY_MIN)
                    @Suppress("DEPRECATION")
                    setDefaults(0)
                }
            }
            .build()
        startForeground(NOTIFICATION_ID, notification)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onBind(intent: Intent?): IBinder? = null

    private companion object {
        const val CHANNEL_ID = "kinly_service_quiet_v2"
        const val NOTIFICATION_ID = 1
    }
}
