package com.example.pitchoune_timer

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.provider.Settings
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Keeps the child on Pitchoune Timer while a choice is pending: countdown
 * paused or ended, and in child mode the choose screen.
 *
 * While [active], leaving the app (Home, Recents, another app) shows a
 * full-screen window *over every other app* (TYPE_APPLICATION_OVERLAY, allowed
 * by the "Display over other apps" permission). Its only button brings
 * Pitchoune Timer back. The window is removed as soon as the app is visible
 * again, and for good when the child has made a choice. In child mode, the
 * same window also invites the child to open the app after an unlock, when
 * Android refused to open it directly ([invite]).
 */
object Guard {
    var active = false
        private set

    private var view: View? = null

    /** Texts of the window, given by the Dart code for each situation. */
    private var title = "Time's up!"
    private var message = "Go back to Pitchoune Timer\nto choose what to do next."

    fun setActive(context: Context, on: Boolean, title: String? = null, message: String? = null) {
        if (title != null) this.title = title
        if (message != null) this.message = message
        active = on
        if (!on) hide(context)
        Log.d(Alarm.TAG, "Guard ${if (on) "on" else "off"}")
    }

    /** Called when the app goes to the background. */
    fun show(context: Context) {
        if (!active) return
        showWindow(context, title, message)
    }

    /**
     * Child mode, after an unlock, when Android did not let the app come to
     * the front by itself: the same window, inviting the child to open it.
     * A tap on our own window is always allowed to open the app.
     */
    fun invite(context: Context) {
        showWindow(context, "Pitchoune Timer", "Tap the button to choose\nhow much time you take.")
    }

    private fun showWindow(context: Context, title: String, message: String) {
        val app = context.applicationContext
        if (view != null) return
        if (!Settings.canDrawOverlays(app)) {
            Log.w(Alarm.TAG, "Guard: \"Display over other apps\" not granted")
            return
        }
        val v = buildView(app, title, message)
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.OPAQUE
        )
        app.getSystemService(WindowManager::class.java).addView(v, params)
        view = v
        Log.d(Alarm.TAG, "Guard window shown")
    }

    /** Called when the app is visible again. */
    fun hide(context: Context) {
        val v = view ?: return
        try {
            context.applicationContext.getSystemService(WindowManager::class.java).removeView(v)
        } catch (e: Exception) {
            Log.w(Alarm.TAG, "Guard: cannot remove the window", e)
        }
        view = null
    }

    private fun buildView(context: Context, titleText: String, messageText: String): View {
        fun dp(value: Float) = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP, value, context.resources.displayMetrics
        ).toInt()

        val emoji = TextView(context).apply {
            text = "⏰"
            textSize = 72f
            gravity = Gravity.CENTER
        }
        val title = TextView(context).apply {
            text = titleText
            textSize = 34f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(0, dp(16f), 0, dp(8f))
        }
        val message = TextView(context).apply {
            text = messageText
            textSize = 20f
            setTextColor(Color.parseColor("#E6E3FF"))
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, dp(32f))
        }
        val button = Button(context).apply {
            text = "Back to Pitchoune Timer"
            textSize = 20f
            isAllCaps = false
            setTextColor(Color.WHITE)
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#FFA62B"))
                cornerRadius = dp(32f).toFloat()
            }
            setPadding(dp(32f), dp(16f), dp(32f), dp(16f))
            setOnClickListener {
                // A click on our own visible window may start our activity.
                context.startActivity(
                    Intent(context, MainActivity::class.java).addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                    )
                )
                hide(context)
            }
        }
        return LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#2B2350"))
            setPadding(dp(32f), dp(32f), dp(32f), dp(32f))
            addView(emoji)
            addView(title)
            addView(message)
            addView(button)
        }
    }
}
