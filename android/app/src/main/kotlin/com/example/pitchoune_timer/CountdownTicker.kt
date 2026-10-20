package com.example.pitchoune_timer

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log

/**
 * Last minute of a countdown: redraws the status bar icon every second.
 *
 * Alarms cannot do it: Android never fires an app's alarm less than about
 * 5 seconds after it was set. And a plain timer stops as soon as Android
 * freezes the app in the background. So for the last minute, the countdown
 * notification becomes the notification of this short *foreground service*,
 * which keeps the process awake and ticks with a Handler.
 *
 * Type "shortService" (Android 14+): meant for jobs of at most 3 minutes, no
 * special permission needed.
 */
class CountdownTicker : Service() {

    private val handler = Handler(Looper.getMainLooper())

    private val tick = object : Runnable {
        override fun run() {
            val nextAt = CountdownNotification.post(this@CountdownTicker)
            if (nextAt == null) {
                stopSelf() // countdown over or hidden
            } else {
                handler.postDelayed(this, (nextAt - System.currentTimeMillis()).coerceAtLeast(50))
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = CountdownNotification.current(this)
        if (notification == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                CountdownNotification.NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE
            )
        } else {
            startForeground(CountdownNotification.NOTIFICATION_ID, notification)
        }
        handler.removeCallbacks(tick)
        handler.post(tick)
        return START_NOT_STICKY
    }

    /** Android 14+: a short service has run for 3 minutes (should never happen). */
    override fun onTimeout(startId: Int) {
        stopSelf()
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        running = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        var running = false
            private set

        /** Returns false if Android refused to start it (the caller falls back to alarms). */
        fun start(context: Context): Boolean {
            if (running) return true
            return try {
                val intent = Intent(context, CountdownTicker::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                running = true
                Log.d(Alarm.TAG, "Countdown ticker started (last minute)")
                true
            } catch (e: Exception) {
                Log.w(Alarm.TAG, "Countdown ticker refused, falling back to alarms", e)
                false
            }
        }

        fun stop(context: Context) {
            if (!running) return
            running = false
            context.stopService(Intent(context, CountdownTicker::class.java))
        }
    }
}
