import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'child.dart';
import 'effects.dart';
import 'parent.dart';
import 'permissions.dart';
import 'theme.dart';
import 'timer_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.store,
    required this.parent,
    this.familyCode,
    this.onLeaveFamily,
    this.onOpenSettings,
  });
  final ChildrenStore store;

  /// Parent mode: needed to change a bank, reset it, or delete a child.
  final ParentLock parent;

  /// Family code to show and share; null hides the family button.
  final String? familyCode;
  final Future<void> Function()? onLeaveFamily;

  /// Opens the settings of this tablet account (after the parent code).
  final VoidCallback? onOpenSettings;

  // --- Actions ---------------------------------------------------------------

  Future<void> _add(BuildContext context) async {
    final r = await askChildDetails(context, title: 'New child', action: 'Add');
    if (r != null) store.add(r.$1, r.$2);
  }

  void _snack(BuildContext context, String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _start(BuildContext context, Child c) async {
    if (c.runningElsewhere(store.deviceId)) {
      _snack(context, "${c.name}'s timer is already running on another device.");
      return;
    }
    if (c.balance <= 0) {
      _snack(context, '${c.name} has no time left. A parent can add minutes.');
      return;
    }
    await checkPermissions(context);
    if (!context.mounted) return;
    Navigator.of(context).push(timerRoute(store, c.id, parent: parent));
  }

  void _showOptions(BuildContext context, Child c) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: ChildAvatar(emoji: c.avatar, color: childColor(c.colorIndex), size: 44),
              title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              subtitle: Text(formatBalance(c.balance)),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Edit name or animal'),
              onTap: () async {
                Navigator.of(sheet).pop();
                final r = await askChildDetails(
                  context,
                  title: 'Edit',
                  action: 'Save',
                  name: c.name,
                  avatar: c.avatar,
                );
                if (r != null) store.update(c.id, r.$1, r.$2);
              },
            ),
            ListTile(
              leading: const Icon(Icons.restart_alt_rounded),
              title: const Text('Reset time to zero'),
              trailing: parent.unlocked ? null : const Icon(Icons.lock_rounded, size: 18),
              onTap: () async {
                Navigator.of(sheet).pop();
                if (await parent.ensure(context)) store.resetToZero(c.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_rounded, color: Colors.redAccent),
              title: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
              trailing: parent.unlocked ? null : const Icon(Icons.lock_rounded, size: 18),
              onTap: () async {
                Navigator.of(sheet).pop();
                if (!await parent.ensure(context) || !context.mounted) return;
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: Text('Delete ${c.name}?'),
                    content: const Text('Their remaining time will be lost.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Cancel')),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                        onPressed: () => Navigator.of(d).pop(true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (ok == true) store.remove(c.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Family code to type on the other devices, and leaving the family.
  void _showFamily(BuildContext context) {
    final code = familyCode!;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Family code', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              const Text(
                'Type this code on another device to share the time banks with it. '
                'Keep it within the family: it is the key to your data.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SelectableText(
                code,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: kPurple,
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: code));
                  Navigator.of(sheet).pop();
                  _snack(context, 'Family code copied');
                },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copy'),
              ),
              if (onLeaveFamily != null) ...[
                const Divider(height: 32),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                  onPressed: () async {
                    Navigator.of(sheet).pop();
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (d) => AlertDialog(
                        title: const Text('Leave this family?'),
                        content: const Text(
                          'This device will no longer see the children. They stay available on '
                          'the other devices, and you can join again with the family code.',
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Cancel')),
                          FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                            onPressed: () => Navigator.of(d).pop(true),
                            child: const Text('Leave'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) await onLeaveFamily!();
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Leave this family'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // --- Display ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [kBackgroundTop, kBackgroundBottom],
                ),
              ),
            ),
          ),
          const Positioned.fill(child: BubbleBackground()),
          SafeArea(
            child: ListenableBuilder(
              listenable: Listenable.merge([store, parent]),
              builder: (context, _) {
                final children = store.children;
                return CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 8, 0),
                        child: Row(
                          children: [
                            const Expanded(child: PitchouneTitle()),
                            if (onOpenSettings != null)
                              IconButton(
                                tooltip: 'Settings',
                                iconSize: 28,
                                color: kInk,
                                onPressed: () async {
                                  if (await parent.ensure(context)) onOpenSettings!();
                                },
                                icon: const Icon(Icons.settings_rounded),
                              ),
                            if (familyCode != null)
                              IconButton(
                                tooltip: 'Family',
                                iconSize: 30,
                                color: kInk,
                                onPressed: () => _showFamily(context),
                                icon: const Icon(Icons.family_restroom_rounded),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (parent.unlocked)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: ParentBanner(lock: parent),
                        ),
                      ),
                    if (children.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyState(onAdd: () => _add(context)),
                      )
                    else ...[
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.only(top: 4, bottom: 8),
                          child: Text(
                            'Tap a child to start their timer',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: kInk, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                        sliver: SliverList.separated(
                          itemCount: children.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 16),
                          itemBuilder: (context, i) {
                            final c = children[i];
                            return ChildCard(
                              key: ValueKey(c.id),
                              kid: c,
                              runningElsewhere: c.runningElsewhere(store.deviceId),
                              locked: !parent.unlocked,
                              onUnlock: () => parent.ensure(context),
                              onStart: () => _start(context, c),
                              onOptions: () => _showOptions(context, c),
                              onPlus: () => store.addMinutes(c.id, 1),
                              onMinus: () => store.addMinutes(c.id, -1),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        backgroundColor: kPurple,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add a child', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// A child's card: avatar, name, balance, − and + buttons
// ---------------------------------------------------------------------------

class ChildCard extends StatefulWidget {
  const ChildCard({
    super.key,
    required this.kid,
    this.runningElsewhere = false,
    this.locked = false,
    this.onUnlock,
    required this.onStart,
    required this.onOptions,
    required this.onPlus,
    required this.onMinus,
  });

  final Child kid;

  /// A countdown for this child is running on another device.
  final bool runningElsewhere;

  /// Bank changes need the parent code: a lock replaces − and +.
  final bool locked;
  final VoidCallback? onUnlock;
  final VoidCallback onStart, onOptions, onPlus, onMinus;

  @override
  State<ChildCard> createState() => _ChildCardState();
}

class _ChildCardState extends State<ChildCard> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.kid;
    final color = childColor(c.colorIndex);
    final empty = c.balance <= 0;

    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onStart,
      onLongPress: widget.onOptions,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: color, width: 3),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45), offset: const Offset(0, 6))],
          ),
          child: Row(
            children: [
              ChildAvatar(emoji: c.avatar, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: kInk),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                      child: Text(
                        empty ? 'No time left' : formatBalance(c.balance),
                        key: ValueKey(c.balance),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: empty ? Colors.black38 : darken(color),
                        ),
                      ),
                    ),
                    if (widget.runningElsewhere)
                      Row(
                        children: [
                          Icon(Icons.timer_rounded, size: 16, color: color),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'In use until ${TimeOfDay.fromDateTime(c.runningUntil!).format(context)}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, color: Colors.black54),
                            ),
                          ),
                        ],
                      )
                    else if (!empty)
                      Row(
                        children: [
                          Icon(Icons.play_circle_fill_rounded, size: 16, color: color),
                          const SizedBox(width: 4),
                          const Text('Start', style: TextStyle(fontSize: 13, color: Colors.black54)),
                        ],
                      ),
                  ],
                ),
              ),
              if (widget.locked)
                RoundButton(
                  icon: Icons.lock_rounded,
                  color: kInk.withValues(alpha: 0.35),
                  size: 44,
                  label: 'Parent code to change the time',
                  onPressed: widget.onUnlock,
                )
              else ...[
                RoundButton(
                  icon: Icons.remove_rounded,
                  color: color,
                  size: 44,
                  repeat: true,
                  label: 'Remove one minute',
                  onPressed: empty ? null : widget.onMinus,
                ),
                const SizedBox(width: 10),
                RoundButton(
                  icon: Icons.add_rounded,
                  color: color,
                  size: 44,
                  repeat: true,
                  label: 'Add one minute',
                  onPressed: widget.onPlus,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🧸', style: TextStyle(fontSize: 90)),
          const SizedBox(height: 12),
          const Text(
            'No children yet',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: kInk),
          ),
          const SizedBox(height: 8),
          const Text(
            'Add a child, then give them minutes with the + button (parent code needed).',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.black54),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAdd,
            style: FilledButton.styleFrom(
              backgroundColor: kPurple,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Add a child', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add / edit dialog: name + animal
// ---------------------------------------------------------------------------

Future<(String, String)?> askChildDetails(
  BuildContext context, {
  required String title,
  required String action,
  String name = '',
  String? avatar,
}) {
  return showDialog<(String, String)>(
    context: context,
    builder: (_) => _ChildDialog(
      title: title,
      action: action,
      name: name,
      avatar: avatar ?? avatars[Random().nextInt(avatars.length)],
    ),
  );
}

class _ChildDialog extends StatefulWidget {
  const _ChildDialog({
    required this.title,
    required this.action,
    required this.name,
    required this.avatar,
  });

  final String title, action, name, avatar;

  @override
  State<_ChildDialog> createState() => _ChildDialogState();
}

class _ChildDialogState extends State<_ChildDialog> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.name);
  late String _avatar = widget.avatar;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final n = _ctrl.text.trim();
    if (n.isEmpty) return;
    Navigator.of(context).pop((n, _avatar));
  }

  @override
  Widget build(BuildContext context) {
    final valid = _ctrl.text.trim().isNotEmpty;
    return AlertDialog(
      scrollable: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w900)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              maxLength: 20,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Pick an animal', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in avatars)
                  GestureDetector(
                    onTap: () => setState(() => _avatar = a),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: a == _avatar ? kPurple.withValues(alpha: 0.15) : Colors.transparent,
                        border: Border.all(
                          color: a == _avatar ? kPurple : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                      child: AnimatedScale(
                        scale: a == _avatar ? 1.2 : 1,
                        duration: const Duration(milliseconds: 150),
                        child: Text(a, style: const TextStyle(fontSize: 24)),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kPurple),
          onPressed: valid ? _submit : null,
          child: Text(widget.action),
        ),
      ],
    );
  }
}
