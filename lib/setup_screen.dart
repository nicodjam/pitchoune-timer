import 'package:flutter/material.dart';

import 'alarm.dart';
import 'screen.dart';
import 'theme.dart';

/// One thing Android must allow, with how to check and how to ask.
class _Item {
  const _Item({
    required this.emoji,
    required this.title,
    required this.text,
    required this.check,
    required this.ask,
  });
  final String emoji;
  final String title;
  final String text;
  final Future<bool> Function() check;
  final Future<void> Function() ask;
}

List<_Item> _items({required bool childMode}) => [
      _Item(
        emoji: '🎉',
        title: 'Display over other apps',
        text: 'Shows the end of a countdown over the app in use, and keeps the child on '
            'Pitchoune Timer until they make a choice.',
        check: Alarm.hasPermission,
        ask: Alarm.requestPermission,
      ),
      _Item(
        emoji: '⏱️',
        title: 'Notifications',
        text: 'The time left in the status bar during a countdown.',
        check: Screen.canNotify,
        ask: Screen.requestNotify,
      ),
      _Item(
        emoji: '🔋',
        title: 'No battery restriction',
        text: 'So that Android does not stop the alarms and the child mode in the '
            'background. In the next screen: Battery → Unrestricted.',
        check: Screen.batteryUnrestricted,
        ask: Screen.openAppSettings,
      ),
      if (childMode)
        _Item(
          emoji: '🏠',
          title: 'Home screen of this account',
          text: 'Pitchoune Timer opens after a restart and on the Home button; the child '
              'opens their apps from it. In the next screen, choose "Pitchoune Timer".',
          check: Screen.isHome,
          ask: Screen.openHomeSettings,
        ),
    ];

/// Is everything allowed? (Always true outside Android.)
Future<bool> setupComplete({required bool childMode}) async {
  if (!Screen.available) return true;
  for (final item in _items(childMode: childMode)) {
    if (!await item.check()) return false;
  }
  return true;
}

bool _shownThisLaunch = false;

/// Shows [SetupScreen] if something is missing, at most once per app launch
/// unless [force] (the parent changed the mode, or opened it from the settings).
Future<void> showSetupIfNeeded(
  NavigatorState navigator, {
  required bool childMode,
  bool force = false,
}) async {
  if (_shownThisLaunch && !force) return;
  if (await setupComplete(childMode: childMode)) return;
  _shownThisLaunch = true;
  await navigator.push(MaterialPageRoute<void>(
    builder: (_) => SetupScreen(childMode: childMode),
  ));
}

/// Everything Pitchoune Timer needs from Android, on one screen, asked once
/// when the app is set up instead of at different moments of its use. Each
/// line shows whether it is allowed, and a button opens the right system
/// screen; the list is checked again when the app comes back from it.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.childMode});
  final bool childMode;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> with WidgetsBindingObserver {
  late final List<_Item> _list = _items(childMode: widget.childMode);
  List<bool>? _granted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Screen.suspendGuard(true);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Screen.suspendGuard(false);
    super.dispose();
  }

  // Back from a system screen: check again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final granted = [for (final item in _list) await item.check()];
    if (mounted) setState(() => _granted = granted);
  }

  @override
  Widget build(BuildContext context) {
    final granted = _granted;
    final done = granted != null && granted.every((g) => g);
    return Scaffold(
      backgroundColor: kBackgroundTop,
      appBar: AppBar(
        backgroundColor: kBackgroundTop,
        title: const Text('Setup', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: granted == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  done
                      ? 'All set! Pitchoune Timer has everything it needs on this tablet account.'
                      : 'Pitchoune Timer needs a few permissions from Android. Tap each '
                          'button, allow, then come back here.',
                  style: const TextStyle(fontSize: 16, color: kInk),
                ),
                const SizedBox(height: 16),
                for (var i = 0; i < _list.length; i++)
                  Card(
                    color: Colors.white,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: Text(_list[i].emoji, style: const TextStyle(fontSize: 32)),
                      title: Text(_list[i].title, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(_list[i].text),
                      trailing: granted[i]
                          ? const Icon(Icons.check_circle_rounded, color: Colors.green, size: 32)
                          : FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: kPurple),
                              onPressed: _list[i].ask,
                              child: const Text('Allow'),
                            ),
                    ),
                  ),
                const SizedBox(height: 24),
                Center(
                  child: done
                      ? FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: kPurple),
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Done'),
                        )
                      : TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Later'),
                        ),
                ),
              ],
            ),
    );
  }
}
