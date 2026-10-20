import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridge to the native Android code (MainActivity.kt / Alarm.kt).
///
/// When a countdown starts, a system alarm is scheduled for the end time.
/// At that time, Android brings Pitchoune Timer back to the foreground, over
/// the current app (even over the lock screen), and plays a sound.
/// When the countdown empties the bank, a second alarm puts the device to
/// sleep shortly after.
/// On any platform other than Android, these methods do nothing.
class Alarm {
  static const _channel = MethodChannel('pitchoune/alarm');

  static bool get available => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Delay between the end of a countdown that empties the bank and the
  /// device going to sleep.
  static const sleepDelay = Duration(seconds: 15);

  /// Schedules the end-of-countdown alarm. With [thenSleep], a second alarm
  /// puts the device to sleep [sleepDelay] later (bank empty).
  static Future<void> schedule(DateTime end, String name, {bool thenSleep = false}) =>
      _call('schedule', {
        'endMs': end.millisecondsSinceEpoch,
        'name': name,
        'sleepAfterMs': thenSleep ? sleepDelay.inMilliseconds : null,
      });

  /// Cancels both the end-of-countdown alarm and the sleep alarm.
  static Future<void> cancel() => _call('cancel');

  /// Cancels only the sleep alarm (the bank was refilled in the meantime).
  static Future<void> cancelSleep() => _call('cancelSleep');

  /// Opens the system "Display over other apps" screen.
  static Future<void> requestPermission() => _call('requestPermission');

  /// Has the user allowed the app to display over other apps?
  static Future<bool> hasPermission() async {
    if (!available) return true;
    try {
      return await _channel.invokeMethod<bool>('hasPermission') ?? false;
    } catch (e) {
      // Native code missing (MainActivity.kt not compiled?):
      // don't nag the user, but report it in the logs.
      debugPrint('Alarm.hasPermission: $e');
      return true;
    }
  }

  static Future<void> _call(String method, [Map<String, Object?>? args]) async {
    if (!available) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (e) {
      debugPrint('Alarm.$method: $e');
    }
  }
}
