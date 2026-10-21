package com.example.pitchoune_timer

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {


    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d(Alarm.TAG, "Channels pitchoune/alarm and pitchoune/screen registered")
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pitchoune/alarm")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "schedule" -> {
                        val endMs = call.argument<Number>("endMs")!!.toLong()
                        val name = call.argument<String>("name") ?: ""
                        Alarm.schedule(this, endMs, name)
                        result.success(null)
                    }
                    "cancel" -> {
                        Alarm.cancel(this)
                        result.success(null)
                    }
                    "hasPermission" -> result.success(Settings.canDrawOverlays(this))
                    "requestPermission" -> {
                        startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            )
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // App window and device screen.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pitchoune/screen")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Keeps the screen awake while a countdown is running and visible.
                    "keepScreenOn" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        if (on) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        Log.d(Alarm.TAG, "Keep screen on: $on")
                        result.success(null)
                    }
                    // Back to the app that was in front before the alarm.
                    "moveToBack" -> {
                        moveTaskToBack(true)
                        Log.d(Alarm.TAG, "App sent to the background")
                        result.success(null)
                    }
                    // Countdown in the status bar (CountdownNotification.kt)
                    "showCountdown" -> {
                        CountdownNotification.show(
                            this,
                            call.argument<String>("name") ?: "",
                            call.argument<Number>("endMs")!!.toLong()
                        )
                        result.success(null)
                    }
                    "hideCountdown" -> {
                        CountdownNotification.hide(this)
                        result.success(null)
                    }
                    "canNotify" -> result.success(CountdownNotification.canPost(this))
                    // Settings screen: "1.0.0+4" (version name + build number).
                    "appVersion" -> {
                        val info = packageManager.getPackageInfo(packageName, 0)
                        val build = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            info.longVersionCode
                        } else {
                            @Suppress("DEPRECATION") info.versionCode.toLong()
                        }
                        result.success("${info.versionName}+$build")
                    }
                    // Child mode: keep the service that opens the app at every unlock.
                    "setChildMode" -> {
                        val on = call.argument<Boolean>("on") == true
                        if (on) ChildMode.start(this) else ChildMode.stop(this)
                        ChildMode.setHome(this, on)
                        result.success(null)
                    }
                    // Child mode: Pitchoune Timer as the home screen (HomeActivity.kt).
                    "isHome" -> result.success(ChildMode.isHome(this))
                    "openHomeSettings" -> {
                        try {
                            startActivity(ChildMode.homeSettingsIntent())
                        } catch (e: Exception) {
                            startActivity(Intent(Settings.ACTION_SETTINGS))
                        }
                        result.success(null)
                    }
                    // The account's apps, opened from Pitchoune Timer (Apps.kt).
                    "listApps" -> Thread {
                        val apps = Apps.list(this)
                        runOnUiThread { result.success(apps) }
                    }.start()
                    "launchApp" -> result.success(Apps.launch(this, call.argument<String>("package")!!))
                    "requestNotify" -> {
                        // Android shows its prompt at most twice; after that,
                        // only the app's notification settings can change it.
                        val prefs = getSharedPreferences("pitchoune_setup", MODE_PRIVATE)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                            prefs.getInt("notifyAsked", 0) < 2
                        ) {
                            prefs.edit().putInt("notifyAsked", prefs.getInt("notifyAsked", 0) + 1).apply()
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 42)
                        } else {
                            startActivity(
                                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            )
                        }
                        result.success(null)
                    }
                    // Keep the child on the app until they make a choice (Guard.kt).
                    "setBlocked" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        Guard.setActive(
                            this,
                            on,
                            call.argument<String>("title"),
                            call.argument<String>("message")
                        )
                        // Countdown ended while another app was in front: cover it now.
                        if (on && !visible) Guard.show(this)
                        result.success(null)
                    }
                    // Setup or settings screen open: no guard over the system screens.
                    "suspendGuard" -> {
                        Guard.suspended = call.argument<Boolean>("on") == true
                        result.success(null)
                    }
                    "isBatteryUnrestricted" -> result.success(
                        getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(packageName)
                    )
                    // Setup screen: the app's page, where Battery → Unrestricted is.
                    "openAppSettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    companion object {
        /** True between onStart and onStop: the app is on screen. */
        @Volatile
        var visible = false
            private set
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        showOverLockScreen(intent)
        // Child mode: make sure the unlock service runs (e.g. after an app update).
        if (ChildMode.isOn(this)) ChildMode.start(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        showOverLockScreen(intent)
    }

    override fun onStart() {
        super.onStart()
        visible = true
        Guard.hide(this)
    }

    override fun onStop() {
        super.onStop()
        visible = false
        // Leaving the app while a choice is pending: cover the other apps.
        if (Guard.active && !isChangingConfigurations) Guard.show(this)
        // Outside of an alarm, the app behaves normally again (hidden by the lock screen).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(false)
            setTurnScreenOn(false)
        }
    }

    /** Launched by the alarm: turn the screen on and show over the lock screen. */
    private fun showOverLockScreen(intent: Intent?) {
        if (intent?.getBooleanExtra(Alarm.EXTRA_ALARM, false) == true &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1
        ) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
    }
}
