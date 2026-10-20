import 'package:flutter/material.dart';

import 'alarm.dart';
import 'screen.dart';
import 'theme.dart';

// What the timer needs from Android, asked from the screen that starts a
// countdown (home screen in parent mode, timer screen in child mode).

bool _overlayAsked = false;
bool _sleepAsked = false;
bool _notifyAsked = false;

/// Once per app launch and per permission, offers to grant what the timer
/// needs: "Display over other apps" (end of countdown shown over other apps),
/// the device administrator right (sleep) and notifications (time left in
/// the status bar).
/// At most one request per countdown start.
Future<void> checkPermissions(BuildContext context) async {
  if (!Alarm.available) return;
  if (!_overlayAsked && !await Alarm.hasPermission()) {
    _overlayAsked = true;
    if (!context.mounted) return;
    final ok = await _askPermission(
      context,
      emoji: '🎉',
      title: 'Show the end of the timer',
      text: 'To show the confetti over other apps when time is up, '
          'allow Pitchoune Timer to "Display over other apps".',
    );
    if (ok) await Alarm.requestPermission();
    return;
  }
  if (!_sleepAsked && !await Screen.canSleep()) {
    _sleepAsked = true;
    if (!context.mounted) return;
    final ok = await _askPermission(
      context,
      emoji: '😴',
      title: 'Sleep when time is up',
      text: "When a child's bank is empty, Pitchoune Timer can put the tablet to sleep "
          '${Alarm.sleepDelay.inSeconds} seconds after the alarm. Android asks you to make '
          'the app a "device administrator", limited to locking the screen.',
    );
    if (ok) await Screen.requestSleepPermission();
    return;
  }
  if (!_notifyAsked && !await Screen.canNotify()) {
    _notifyAsked = true;
    if (!context.mounted) return;
    final ok = await _askPermission(
      context,
      emoji: '⏱️',
      title: 'Time left in the status bar',
      text: 'During a countdown, Pitchoune Timer can show the time left next to the clock, '
          'even in other apps. Android asks you to allow its notifications.',
    );
    if (ok) await Screen.requestNotify();
  }
}

Future<bool> _askPermission(
  BuildContext context, {
  required String emoji,
  required String title,
  required String text,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      icon: Text(emoji, style: const TextStyle(fontSize: 40)),
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Later')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kPurple),
          onPressed: () => Navigator.of(d).pop(true),
          child: const Text('Allow'),
        ),
      ],
    ),
  );
  return ok == true;
}
