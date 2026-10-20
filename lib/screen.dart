import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridge to MainActivity.kt for everything about the app window and the
/// device screen. On any platform other than Android, it does nothing.
class Screen {
  static const _channel = MethodChannel('pitchoune/screen');

  static bool get available => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Keeps the screen awake. Android only honours it while the app is
  /// visible, so the phone still sleeps normally behind another app.
  static Future<void> keepOn(bool on) => _call('keepScreenOn', {'on': on});

  /// Sends the app to the background, revealing the app that was in front
  /// before the alarm brought Pitchoune Timer forward.
  static Future<void> sendToBack() => _call('moveToBack');

  /// Is the app allowed to put the device to sleep (device administrator)?
  static Future<bool> canSleep() async {
    if (!available) return false;
    try {
      return await _channel.invokeMethod<bool>('canSleep') ?? false;
    } catch (e) {
      debugPrint('Screen.canSleep: $e');
      return false;
    }
  }

  /// Opens the system screen that makes the app a device administrator,
  /// limited to the "lock the screen" policy.
  static Future<void> requestSleepPermission() => _call('requestSleepPermission');

  /// Puts the device to sleep now. Returns false if the app is not allowed to.
  static Future<bool> sleepNow() async {
    if (!available) return false;
    try {
      return await _channel.invokeMethod<bool>('sleepNow') ?? false;
    } catch (e) {
      debugPrint('Screen.sleepNow: $e');
      return false;
    }
  }

  /// While blocked, leaving the app shows a full-screen window over the other
  /// apps, with [title] and [message], whose only button brings Pitchoune
  /// Timer back.
  static Future<void> setBlocked(bool on, {String? title, String? message}) =>
      _call('setBlocked', {'on': on, 'title': title, 'message': message});

  /// Shows the countdown in the status bar until [end] (a chip next to the
  /// clock on Android 16+, a notification with a countdown before).
  static Future<void> showCountdown(String name, DateTime end) =>
      _call('showCountdown', {'name': name, 'endMs': end.millisecondsSinceEpoch});

  static Future<void> hideCountdown() => _call('hideCountdown');

  /// May the app post notifications (runtime permission since Android 13)?
  static Future<bool> canNotify() async {
    if (!available) return true;
    try {
      return await _channel.invokeMethod<bool>('canNotify') ?? false;
    } catch (e) {
      debugPrint('Screen.canNotify: $e');
      return true;
    }
  }

  /// Child mode on this tablet account: a native service reopens the app at
  /// every unlock, and the app is offered as the account's home screen.
  static Future<void> setChildMode(bool on) => _call('setChildMode', {'on': on});

  /// Child mode: is Pitchoune Timer the home screen of this tablet account?
  static Future<bool> isHome() async {
    if (!available) return false;
    try {
      return await _channel.invokeMethod<bool>('isHome') ?? false;
    } catch (e) {
      debugPrint('Screen.isHome: $e');
      return false;
    }
  }

  /// Opens the system screen where the home app is chosen.
  static Future<void> openHomeSettings() => _call('openHomeSettings');

  /// Shows the system "Allow notifications?" prompt.
  static Future<void> requestNotify() => _call('requestNotify');

  static Future<void> _call(String method, [Map<String, Object?>? args]) async {
    if (!available) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (e) {
      debugPrint('Screen.$method: $e');
    }
  }
}
