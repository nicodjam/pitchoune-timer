package com.example.pitchoune_timer

import android.app.admin.DeviceAdminReceiver
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Puts the device to sleep (screen off + locked).
 *
 * Android only lets an app do this if the user has made it a *device
 * administrator*. Pitchoune Timer asks for a single policy: "lock the screen"
 * (see res/xml/device_admin.xml). Nothing else is controlled.
 */
object Sleep {
    private fun admin(context: Context) = ComponentName(context, SleepAdminReceiver::class.java)

    private fun dpm(context: Context) = context.getSystemService(DevicePolicyManager::class.java)

    fun isAllowed(context: Context): Boolean = dpm(context).isAdminActive(admin(context))

    /** System screen where the user activates the device administrator. */
    fun permissionIntent(context: Context): Intent =
        Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
            .putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, admin(context))
            .putExtra(
                DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                "Pitchoune Timer puts the tablet to sleep when a child's time bank is empty."
            )

    fun now(context: Context) {
        if (!isAllowed(context)) {
            Log.w(Alarm.TAG, "Cannot sleep: device administrator not activated")
            return
        }
        dpm(context).lockNow()
        Log.d(Alarm.TAG, "Device put to sleep")
    }
}

/** Required by Android to declare the app as a device administrator. */
class SleepAdminReceiver : DeviceAdminReceiver()
