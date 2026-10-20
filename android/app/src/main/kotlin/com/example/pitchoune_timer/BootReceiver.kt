package com.example.pitchoune_timer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * Child mode after a restart (or an app update): starts the service that
 * reopens the app at every unlock (ChildModeService), which also opens the
 * app right away.
 *
 * BOOT_COMPLETED arrives after the first unlock, once the user's storage is
 * readable (sometimes many seconds later on Samsung); on a tablet with several
 * users, each user receives it when they first log in. The unlock is already
 * past by then, hence the immediate opening.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val childMode = ChildMode.isOn(context)
        Log.d(Alarm.TAG, "${intent.action}: child mode = $childMode")
        if (!childMode) return
        if (ChildMode.start(context, openApp = true)) return

        // The service was refused: open the app from here. goAsync keeps this
        // receiver (and so the process) alive for the check that follows.
        val pending = goAsync()
        ChildMode.bringToFront(context, check = true)
        Handler(Looper.getMainLooper()).postDelayed({ pending.finish() }, 3000)
    }
}
