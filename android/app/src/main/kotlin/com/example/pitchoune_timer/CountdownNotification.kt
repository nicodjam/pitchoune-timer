package com.example.pitchoune_timer

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.util.Log
import kotlin.math.ceil

/**
 * Shows the running countdown outside the app.
 *
 * Apps cannot write text in the status bar, but a notification's small icon
 * is shown there. So the icon is **drawn on the fly**: a small stopwatch and
 * the unit on top, the time left below ("12 mn", then in the last minute
 * "60 s", "59 s"…). It is re-posted at every minute change by a system alarm
 * (the Dart code may be frozen in the background), then every second during
 * the last minute by a short foreground service (CountdownTicker).
 *
 * The notification itself carries a live chronometer (seconds included) in
 * the notification shade, and asks to become a Live Update: on Android 16
 * devices that support it, a chip next to the clock shows the time left.
 * It removes itself at the end time (setTimeoutAfter), even if the app is dead.
 */
object CountdownNotification {
    private const val CHANNEL_ID = "countdown"
    const val NOTIFICATION_ID = 1001
    private const val REFRESH_REQUEST = 4244
    private const val PREFS = "pitchoune_countdown"

    /** Notification.EXTRA_REQUEST_PROMOTED_ONGOING (Android 16), as a string so
     *  that the app still compiles against older SDKs. */
    private const val EXTRA_REQUEST_PROMOTED_ONGOING = "android.requestPromotedOngoing"

    fun canPost(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    private fun manager(context: Context) = context.getSystemService(NotificationManager::class.java)

    /** Starts showing the countdown until [endMs]. */
    fun show(context: Context, name: String, endMs: Long) {
        // Remembered natively: the refresh alarm re-posts without the Dart code.
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("name", name).putLong("endMs", endMs).apply()
        refresh(context)
    }

    /** A countdown is running on this device (its end is still ahead). */
    fun isRunning(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getLong("endMs", 0) >
            System.currentTimeMillis()

    fun hide(context: Context) {
        CountdownTicker.stop(context)
        manager(context).cancel(NOTIFICATION_ID)
        context.getSystemService(AlarmManager::class.java).cancel(refreshIntent(context))
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
    }

    /**
     * Re-posts the notification, and plans the next refresh: an alarm at the
     * next minute change, or the ticker service for the last minute (alarms
     * cannot fire every second: Android delays them to at least ~5 s).
     */
    fun refresh(context: Context) {
        val nextAt = post(context) ?: return
        val lastMinute = endMs(context) - System.currentTimeMillis() <= 60_000
        if (lastMinute && CountdownTicker.start(context)) return
        scheduleRefresh(context, nextAt + 200)
    }

    /** What the notification shows now, and when that changes. */
    private class State(val name: String, val endMs: Long, val value: Int, val unit: String, val nextAt: Long)

    private fun endMs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getLong("endMs", 0)

    private fun state(context: Context): State? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val endMs = prefs.getLong("endMs", 0)
        val name = prefs.getString("name", "") ?: ""
        val left = endMs - System.currentTimeMillis()
        if (left <= 0) return null
        // Minutes (rounded up) while more than one minute is left, then
        // every second. nextAt: when the shown value changes.
        return if (left > 60_000) {
            val value = ceil(left / 60_000.0).toInt()
            State(name, endMs, value, "mn", endMs - (value - 1) * 60_000L)
        } else {
            val value = ceil(left / 1_000.0).toInt()
            State(name, endMs, value, "s", endMs - (value - 1) * 1_000L)
        }
    }

    /** The notification as it should look now; null once the countdown is over. */
    fun current(context: Context): Notification? {
        val s = state(context) ?: return null
        ensureChannel(context)
        return build(context, s.name, s.endMs, s.value, s.unit)
    }

    /**
     * Posts the notification as it should look now. Returns when it must be
     * redrawn, or null when there is nothing more to show (the countdown is
     * over: everything is cleaned up).
     */
    fun post(context: Context): Long? {
        val s = state(context)
        if (s == null) {
            hide(context)
            return null
        }
        if (!canPost(context)) {
            Log.w(Alarm.TAG, "Countdown notification: permission not granted")
            return null
        }
        ensureChannel(context)
        manager(context).notify(NOTIFICATION_ID, build(context, s.name, s.endMs, s.value, s.unit))
        return if (s.nextAt < s.endMs) s.nextAt else s.endMs
    }

    private fun build(context: Context, name: String, endMs: Long, value: Int, unit: String): Notification {
        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            Notification.Builder(context)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            builder.setSmallIcon(Icon.createWithBitmap(timeIcon(value, unit)))
        } else {
            builder.setSmallIcon(R.drawable.ic_stat_timer)
        }
        builder
            .setContentTitle("$name's time: $value $unit left")
            .setContentText("Pitchoune Timer")
            .setContentIntent(open)
            .setOngoing(true) // the child cannot swipe it away; required for a Live Update
            .setOnlyAlertOnce(true)
            .setShowWhen(true)
            .setWhen(endMs)
            .setUsesChronometer(true)
            .addExtras(Bundle().apply { putBoolean(EXTRA_REQUEST_PROMOTED_ONGOING, true) })
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) builder.setChronometerCountDown(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder.setTimeoutAfter((endMs - System.currentTimeMillis()).coerceAtLeast(0))
        }
        if (Build.VERSION.SDK_INT >= 36) {
            // Same as the extra above, through the official API when it exists.
            runCatching {
                Notification.Builder::class.java
                    .getMethod("setRequestPromotedOngoing", Boolean::class.javaPrimitiveType)
                    .invoke(builder, true)
            }
        }
        return builder.build()
    }

    /**
     * The time left, drawn as a status bar icon: a small stopwatch and the unit
     * on the top line, the number in big below. Android keeps only the alpha
     * channel of status bar icons and tints them itself, so everything is drawn
     * opaque on a transparent background.
     */
    private fun timeIcon(value: Int, unit: String): Bitmap {
        val size = 96f
        val bitmap = Bitmap.createBitmap(size.toInt(), size.toInt(), Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val bold = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)

        // Stopwatch pictogram: dial, top button, one hand.
        val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.STROKE
            strokeWidth = 5f
            strokeCap = Paint.Cap.ROUND
        }
        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
        val cx = 20f
        val cy = 22f
        val r = 12f
        canvas.drawCircle(cx, cy, r, stroke)
        canvas.drawRect(cx - 4f, cy - r - 8f, cx + 4f, cy - r - 2f, fill)
        canvas.drawLine(cx, cy, cx + 6f, cy - 7f, stroke)

        // Unit, next to the pictogram.
        val unitPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            typeface = bold
            textSize = 30f
        }
        canvas.drawText(unit, 40f, 33f, unitPaint)

        // Number, centred in the lower part.
        val text = if (value > 999) "999" else value.toString()
        val numberPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            typeface = bold
            textAlign = Paint.Align.CENTER
            textSize = when (text.length) {
                1 -> 60f
                2 -> 56f
                else -> 42f
            }
        }
        val y = 68f - (numberPaint.descent() + numberPaint.ascent()) / 2f
        canvas.drawText(text, size / 2f, y, numberPaint)
        return bitmap
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        // Default importance (status bar icon), but silent: the countdown must
        // not ring every time it is re-posted.
        val channel = NotificationChannel(CHANNEL_ID, "Countdown", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = "Time left in the running countdown"
            setSound(null, null)
            enableVibration(false)
            setShowBadge(false)
        }
        manager(context).createNotificationChannel(channel)
    }

    private fun refreshIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        REFRESH_REQUEST,
        Intent(context, CountdownRefreshReceiver::class.java),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
    )

    private fun scheduleRefresh(context: Context, atMs: Long) {
        val am = context.getSystemService(AlarmManager::class.java)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()) {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, refreshIntent(context))
        } else {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, refreshIntent(context))
        }
    }
}

/** Wakes up at every minute change to redraw the minutes in the status bar. */
class CountdownRefreshReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        CountdownNotification.refresh(context)
    }
}
