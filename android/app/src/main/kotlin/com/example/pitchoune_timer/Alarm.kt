package com.example.pitchoune_timer

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.os.Build
import android.util.Log

/**
 * Schedules / cancels two alarms:
 * - the end-of-countdown alarm, which brings the app to the foreground;
 * - optionally, the sleep alarm, which locks the device a little later
 *   (used when the countdown empties the child's bank).
 */
object Alarm {
    const val TAG = "Pitchoune"
    const val EXTRA_ALARM = "pitchoune_alarm"
    private const val EXTRA_SLEEP = "pitchoune_sleep"
    private const val END_REQUEST = 4242
    private const val SLEEP_REQUEST = 4243

    private fun pendingIntent(context: Context, request: Int, name: String = ""): PendingIntent {
        val intent = Intent(context, AlarmReceiver::class.java)
            .putExtra("name", name)
            .putExtra(EXTRA_SLEEP, request == SLEEP_REQUEST)
        return PendingIntent.getBroadcast(
            context,
            request,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    private fun set(context: Context, atMs: Long, pi: PendingIntent, what: String) {
        val am = context.getSystemService(AlarmManager::class.java)
        val inSeconds = (atMs - System.currentTimeMillis()) / 1000
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()) {
            // Exact alarm, even in battery-saving (Doze) mode
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, pi)
            Log.d(TAG, "EXACT $what alarm scheduled in $inSeconds s")
        } else {
            // Fallback: Android may delay it by several minutes
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, pi)
            Log.w(TAG, "INEXACT $what alarm (exact alarm permission denied) in $inSeconds s")
        }
    }

    fun schedule(context: Context, endMs: Long, name: String, sleepAfterMs: Long?) {
        set(context, endMs, pendingIntent(context, END_REQUEST, name), "end")
        if (sleepAfterMs != null) {
            set(context, endMs + sleepAfterMs, pendingIntent(context, SLEEP_REQUEST), "sleep")
        } else {
            cancelSleep(context)
        }
    }

    fun cancel(context: Context) {
        context.getSystemService(AlarmManager::class.java)
            .cancel(pendingIntent(context, END_REQUEST))
        cancelSleep(context)
        Log.d(TAG, "Alarms cancelled")
    }

    fun cancelSleep(context: Context) {
        context.getSystemService(AlarmManager::class.java)
            .cancel(pendingIntent(context, SLEEP_REQUEST))
        Log.d(TAG, "Sleep alarm cancelled")
    }

    fun isSleepAlarm(intent: Intent) = intent.getBooleanExtra(EXTRA_SLEEP, false)
}

/**
 * Receives both alarms.
 * - Sleep alarm: locks the device (needs the device administrator right).
 * - End alarm: plays the notification sound and brings Pitchoune Timer back to
 *   the foreground. Starting an activity from the background is only allowed
 *   if the user granted "Display over other apps".
 */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (Alarm.isSleepAlarm(intent)) {
            Log.d(Alarm.TAG, "Sleep alarm received")
            Sleep.now(context)
            return
        }

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
