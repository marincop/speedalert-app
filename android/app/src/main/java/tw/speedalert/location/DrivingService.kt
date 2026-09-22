package tw.speedalert.location

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Foreground service that streams GPS fixes into [LocationBus] while driving.
 * Mirrors the always-on background location of the iOS app.
 */
class DrivingService : Service() {

    private var locationManager: LocationManager? = null
    private val listener = LocationListener { loc -> LocationBus.location.value = loc }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        startForeground(NOTIF_ID, buildNotification())
        try {
            locationManager?.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1000L, 5f, listener)
            locationManager?.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 1000L, 5f, listener)
        } catch (_: SecurityException) {
            // location permission not granted yet
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onDestroy() {
        runCatching { locationManager?.removeUpdates(listener) }
        LocationBus.location.value = null
        super.onDestroy()
    }

    private fun buildNotification(): Notification {
        val channelId = "driving"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            if (nm.getNotificationChannel(channelId) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(channelId, "行車模式", NotificationManager.IMPORTANCE_LOW)
                )
            }
        }
        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("測速提醒")
            .setContentText("行車模式：背景定位中")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    companion object { const val NOTIF_ID = 1001 }
}
