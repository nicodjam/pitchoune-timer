package com.example.pitchoune_timer

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.os.Build
import android.util.Log

/** Schedules / cancels the end-of-countdown alarm, which brings the app to the foreground. */
object Alarm {
    const val TAG = "Pitchoune"
    const val EXTRA_ALARM = "pitchoune_alarm"
    private const val END_REQUEST = 4242

    private fun pendingIntent(context: Context, name: String = ""): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            END_REQUEST,
            Intent(context, AlarmReceiver::class.java).putExtra("name", name),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

    fun schedule(context: Context, endMs: Long, name: String) {
        val am = context.getSystemService(AlarmManager::class.java)
        val pi = pendingIntent(context, name)
        val inSeconds = (endMs - System.currentTimeMillis()) / 1000
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()) {
            // Exact alarm, even in battery-saving (Doze) mode
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, endMs, pi)
            Log.d(TAG, "EXACT end alarm scheduled in $inSeconds s")
        } else {
            // Fallback: Android may delay it by several minutes
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, endMs, pi)
            Log.w(TAG, "INEXACT end alarm (exact alarm permission denied) in $inSeconds s")
        }
    }

    fun cancel(context: Context) {
        context.getSystemService(AlarmManager::class.java).cancel(pendingIntent(context))
        Log.d(TAG, "Alarm cancelled")
    }
}

/**
 * Receives the end alarm: plays the notification sound and brings Pitchoune
 * Timer back to the foreground. Starting an activity from the background is
 * only allowed if the user granted "Display over other apps".
 */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // A sleep alarm left by version 1.0.0 (sleep was removed since).
        if (intent.getBooleanExtra("pitchoune_sleep", false)) return

        Log.d(Alarm.TAG, "End alarm received for ${intent.getStringExtra("name")}")
        try {
            val sound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            RingtoneManager.getRingtone(context, sound)?.play()
        } catch (e: Exception) {
            Log.w(Alarm.TAG, "Cannot play sound", e)
        }

        val launch = Intent(context, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
            putExtra(Alarm.EXTRA_ALARM, true)
        }
        try {
            context.startActivity(launch)
            Log.d(Alarm.TAG, "App brought to the foreground")
        } catch (e: Exception) {
            Log.w(Alarm.TAG, "Cannot show the app (missing permission?)", e)
        }
    }
}
