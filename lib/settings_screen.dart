import 'package:flutter/material.dart';

import 'child.dart';
import 'effects.dart';
import 'screen.dart';
import 'settings.dart';
import 'theme.dart';

/// Settings of this tablet account. Only reachable with the parent code.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.settings, required this.store});
  final DeviceSettings settings;
  final ChildrenStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundTop,
      appBar: AppBar(
        backgroundColor: kBackgroundTop,
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([settings, store]),
        builder: (context, _) {
          final children = store.children;
          final childMode = settings.mode == DeviceMode.child;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Who uses this tablet account?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kInk),
              ),
              const SizedBox(height: 6),
              const Text(
                'These settings only apply to this tablet account. On a tablet with several '
                'accounts (a parent one and a child one), set each account separately.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 16),
              SegmentedButton<DeviceMode>(
                segments: const [
                  ButtonSegment(
                    value: DeviceMode.parent,
                    icon: Icon(Icons.family_restroom_rounded),
                    label: Text('Parent'),
                  ),
                  ButtonSegment(
                    value: DeviceMode.child,
                    icon: Icon(Icons.child_care_rounded),
                    label: Text('Child'),
                  ),
                ],
                selected: {settings.mode},
                onSelectionChanged: (selection) {
                  if (selection.first == DeviceMode.parent) {
                    settings.setParentMode();
                  } else if (children.isNotEmpty) {
                    // Child mode needs a child: keep the previous one if it still
                    // exists, otherwise take the first.
                    final keep = settings.childId != null && store.byId(settings.childId!) != null;
                    settings.setChildMode(keep ? settings.childId! : children.first.id);
                  }
                },
              ),
              const SizedBox(height: 12),
              Text(
                childMode
                    ? 'Child mode: the app opens straight on the countdown of the child below. '
                        'The list of children and the bank changes are no longer shown.'
                    : 'Parent mode: the app shows every child of the family, and lets you '
                        'change their banks with the parent code.',
                style: const TextStyle(color: Colors.black54),
              ),
              if (children.isEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Add a child first (parent mode, home screen) to use child mode.',
                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700),
                ),
              ],
              if (childMode) ...[
                const SizedBox(height: 28),
                const _HomeScreenCard(),
                const SizedBox(height: 28),
                const Text(
                  'Which child?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kInk),
                ),
                const SizedBox(height: 8),
                RadioGroup<String>(
                  groupValue: settings.childId,
                  onChanged: (id) {
                    if (id != null) settings.setChildMode(id);
                  },
                  child: Column(
                    children: [
                      for (final c in children)
                        RadioListTile<String>(
                          value: c.id,
                          secondary: ChildAvatar(
                            emoji: c.avatar,
                            color: childColor(c.colorIndex),
                            size: 44,
                          ),
                          title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Text(formatBalance(c.balance)),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Child mode: makes Pitchoune Timer the home screen of this tablet account,
/// so that Android opens it at login, on the Home button, and when the child
/// leaves another app.
class _HomeScreenCard extends StatefulWidget {
  const _HomeScreenCard();

  @override
  State<_HomeScreenCard> createState() => _HomeScreenCardState();
}

class _HomeScreenCardState extends State<_HomeScreenCard> with WidgetsBindingObserver {
  bool? _isHome;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from the system settings: check again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    // The home activity is enabled just before: give Android a moment.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final isHome = await Screen.isHome();
    if (mounted) setState(() => _isHome = isHome);
  }

  @override
  Widget build(BuildContext context) {
    final isHome = _isHome;
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isHome == true ? Icons.check_circle_rounded : Icons.home_rounded,
                  color: isHome == true ? Colors.green : kInk,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Home screen',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kInk),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              switch (isHome) {
                null => 'Checking…',
                true => 'Pitchoune Timer is the home screen of this account: it opens at '
                    'login, on the Home button and when an app is closed. The child opens '
                    'their apps from it ("My apps") while a countdown runs.',
                false => 'Make Pitchoune Timer the home screen of this account, so that it '
                    'opens at login after a restart, on the Home button and when an app is '
                    'closed. In the next screen, choose "Pitchoune Timer".',
              },
              style: const TextStyle(color: Colors.black54),
            ),
            if (isHome == false) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: Screen.openHomeSettings,
                icon: const Icon(Icons.home_rounded),
                label: const Text('Choose the home screen'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
