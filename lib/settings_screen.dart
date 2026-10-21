import 'package:flutter/material.dart';

import 'child.dart';
import 'effects.dart';
import 'screen.dart';
import 'settings.dart';
import 'setup_screen.dart';
import 'theme.dart';

/// Settings of this tablet account. Only reachable with the parent code.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.settings, required this.store});
  final DeviceSettings settings;
  final ChildrenStore store;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  DeviceSettings get settings => widget.settings;
  ChildrenStore get store => widget.store;
  final Future<String?> _version = Screen.appVersion();

  // In child mode the guard is active behind this screen: keep it off while
  // a parent is here (the setup opens system screens).
  @override
  void initState() {
    super.initState();
    Screen.suspendGuard(true);
  }

  @override
  void dispose() {
    Screen.suspendGuard(false);
    super.dispose();
  }

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
                    // Child mode needs more (home screen): set it up now.
                    showSetupIfNeeded(Navigator.of(context), childMode: true, force: true);
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
              const SizedBox(height: 20),
              Card(
                color: Colors.white,
                child: ListTile(
                  leading: const Icon(Icons.verified_user_rounded, color: kPurple),
                  title: const Text(
                    'Permissions and setup',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text('Everything Android must allow, on one screen'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => SetupScreen(childMode: childMode),
                  )),
                ),
              ),
              if (childMode) ...[
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
              const SizedBox(height: 32),
              // Installed version, as tool/release.sh numbers it.
              FutureBuilder<String?>(
                future: _version,
                builder: (context, snapshot) => Text(
                  snapshot.data == null ? '' : 'Pitchoune Timer ${formatVersion(snapshot.data!)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black45),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
