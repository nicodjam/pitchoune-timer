package com.example.pitchoune_timer

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.Log

/**
 * Child mode: opens Pitchoune Timer every time the tablet is unlocked.
 *
 * Android only announces an unlock (ACTION_USER_PRESENT) to apps that are
 * already running, and only to receivers registered in code. So in child mode
 * the app keeps this small *foreground service* alive: it shows a discreet
 * permanent notification ("Child mode") and listens to unlocks. It is started
 * when child mode is turned on, and after a restart (BootReceiver).
 */
class ChildModeService : Service() {

    private val unlockReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            Log.d(Alarm.TAG, "Child mode: ${intent.action}")
            when (intent.action) {
                // Screen on: open the app already, behind the lock screen, so
                // that it is the first thing seen once unlocked.
                Intent.ACTION_SCREEN_ON -> ChildMode.bringToFront(context)
                // Unlocked: open it (again), and check that it worked.
                Intent.ACTION_USER_PRESENT -> ChildMode.bringToFront(context, check = true)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_USER_PRESENT)
            addAction(Intent.ACTION_SCREEN_ON)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // System broadcasts still reach a non-exported receiver.
            registerReceiver(unlockReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(unlockReceiver, filter)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val openApp = intent?.getBooleanExtra(EXTRA_OPEN_APP, false) == true
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        Log.d(Alarm.TAG, "Child mode service running")
        // After a restart: the unlock is already past, open the app now.
        if (openApp) ChildMode.bringToFront(this, check = true)
        return START_STICKY // restarted by Android if it is ever killed
    }

    override fun onDestroy() {
        unregisterReceiver(unlockReceiver)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Low importance: in the notification shade, no sound, no status bar icon.
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Child mode", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Opens Pitchoune Timer when the tablet is unlocked"
                    setShowBadge(false)
                }
            )
        }
        val open = PendingIntent.getActivity(
            this,
            1,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.drawable.ic_stat_timer)
            .setContentTitle("Pitchoune Timer: child mode")
            .setContentText("The app opens when the tablet is unlocked")
            .setContentIntent(open)
            .setOngoing(true)
            .build()
    }

    companion object {
        const val EXTRA_OPEN_APP = "open_app"
        private const val CHANNEL_ID = "child_mode"
        private const val NOTIFICATION_ID = 1002
    }
}

/** Starting / stopping child mode, and what an unlock does. */
object ChildMode {
    /** Child mode as saved by the Dart side (shared_preferences: "flutter." + key). */
    fun isOn(context: Context): Boolean =
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString("flutter.pitchoune.mode", null) == "child"

    /** Starts the service; with [openApp], it also opens the app. False if refused. */
    fun start(context: Context, openApp: Boolean = false): Boolean {
        val intent = Intent(context, ChildModeService::class.java)
            .putExtra(ChildModeService.EXTRA_OPEN_APP, openApp)
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            true
        } catch (e: Exception) {
            Log.w(Alarm.TAG, "Cannot start the child mode service", e)
            false
        }
    }

    /**
     * Offers Pitchoune Timer as a home screen (HomeActivity) only in child
     * mode. The enabled state of a component is kept per Android user.
     */
    fun setHome(context: Context, on: Boolean) {
        val component = ComponentName(context, HomeActivity::class.java)
        val state = if (on) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        } else {
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        }
        val pm = context.packageManager
        if (pm.getComponentEnabledSetting(component) == state) return
        pm.setComponentEnabledSetting(component, state, PackageManager.DONT_KILL_APP)
        Log.d(Alarm.TAG, "Home screen offered: $on")
    }

    /** Is Pitchoune Timer the home screen of this account? */
    fun isHome(context: Context): Boolean =
        context.packageManager.resolveActivity(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME),
            PackageManager.MATCH_DEFAULT_ONLY
        )?.activityInfo?.packageName == context.packageName

    /** The system screen where the home app is chosen. */
    fun homeSettingsIntent(): Intent =
        Intent(Settings.ACTION_HOME_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    fun stop(context: Context) {
        context.stopService(Intent(context, ChildModeService::class.java))
        Log.d(Alarm.TAG, "Child mode service stopped")
    }

    /**
     * Opens the app, unless the child is using a running countdown elsewhere.
     *
     * Android may silently refuse to open an activity from the background (the
     * "Display over other apps" permission normally allows it, but not every
     * version or manufacturer agrees). With [check], if the app is still not
     * on screen a moment later, the guard window invites the child to open it:
     * a tap on our own window is always allowed to.
     */
    fun bringToFront(context: Context, check: Boolean = false) {
        if (CountdownNotification.isRunning(context)) return
        try {
            context.startActivity(
                Intent(context, MainActivity::class.java).addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                )
            )
            Log.d(Alarm.TAG, "Child mode: app asked to come to the front")
        } catch (e: Exception) {
            Log.w(Alarm.TAG, "Child mode: cannot open the app", e)
        }
        if (!check) return
        Handler(Looper.getMainLooper()).postDelayed({
            if (!MainActivity.visible && !CountdownNotification.isRunning(context)) {
                Log.w(Alarm.TAG, "Child mode: the app did not come to the front, showing the invitation")
                Guard.invite(context)
            }
        }, 1500)
    }
}
