package com.example.pitchoune_timer

import android.app.Activity
import android.content.Intent
import android.os.SystemClock
import android.util.Log

/**
 * Child mode: Pitchoune Timer as the **home screen** of the child's account.
 *
 * Android always starts the home app of an account, even when the app is in
 * the "stopped" state where it receives nothing (no BOOT_COMPLETED, no
 * alarm): at login after a restart, on the Home button, and when the child
 * leaves another app. So this is the one reliable way back to the timer.
 *
 * This activity is only a trampoline: it shows nothing (translucent) and
 * forwards to MainActivity each time it comes to the front. It is enabled only
 * while the account is in child mode (ChildMode.setHome); the child's apps are
 * then opened from Pitchoune Timer's own app list (Apps.kt).
 */
class HomeActivity : Activity() {

    override fun onResume() {
        super.onResume()
        // Safety net against a loop if MainActivity could not stay in front.
        val now = SystemClock.elapsedRealtime()
        if (now - lastForward < 1000) return
        lastForward = now
        Log.d(Alarm.TAG, "Home: opening Pitchoune Timer")
        startActivity(
            Intent(this, MainActivity::class.java).addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
            )
        )
        @Suppress("DEPRECATION")
        overridePendingTransition(0, 0)
    }

    companion object {
        private var lastForward = 0L
    }
}
