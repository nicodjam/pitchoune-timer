import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Parent code of a family that never chose its own (Settings → Parent code).
const kParentCode = '728';

/// A parent code is 4 to 6 digits (the default one, older, has 3).
bool isValidParentCode(String code) => RegExp(r'^[0-9]{4,6}$').hasMatch(code);

/// "Parent mode": unlocked by the parent code, it locks itself again after
/// [duration]. Screens listen to it to show or hide what only a parent may do.
class ParentLock extends ChangeNotifier {
  ParentLock({this.duration = const Duration(minutes: 2)});

  final Duration duration;
  DateTime? _until;

  /// The family's parent code, kept up to date from Firestore by the app
  /// (FamilyService.parentCodeChanges): changed on one device, it changes on
  /// every device of the family.
  String code = kParentCode;
  Timer? _ticker;

  bool get unlocked => _until != null && DateTime.now().isBefore(_until!);

  /// Time left before parent mode locks itself, or zero when locked.
  Duration get remaining => unlocked ? _until!.difference(DateTime.now()) : Duration.zero;

  /// Checks a typed code; unlocks parent mode if it is right.
  bool tryUnlock(String code) {
    if (code != this.code) return false;
    _until = DateTime.now().add(duration);
    _ticker?.cancel();
    // Notifies every second, for the countdown shown on screen, then locks.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!unlocked) lock();
      notifyListeners();
    });
    notifyListeners();
    return true;
  }

  void lock() {
    _until = null;
    _ticker?.cancel();
    _ticker = null;
    notifyListeners();
  }

  /// True if parent mode is on, or once the parent has typed the right code.
  Future<bool> ensure(BuildContext context) async {
    if (unlocked) return true;
    final code = await showDialog<String>(
      context: context,
      builder: (_) => _CodeDialog(expected: this.code),
    );
    return code != null && tryUnlock(code);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

/// Asks for a new parent code, typed twice. Returns it, or null if cancelled.
Future<String?> askNewParentCode(BuildContext context) =>
    showDialog<String>(context: context, builder: (_) => const _NewCodeDialog());

class _NewCodeDialog extends StatefulWidget {
  const _NewCodeDialog();

  @override
  State<_NewCodeDialog> createState() => _NewCodeDialogState();
}

class _NewCodeDialogState extends State<_NewCodeDialog> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  void _save() {
    final code = _first.text;
    setState(() {
      _error = !isValidParentCode(code)
          ? 'The code must have 4 to 6 digits.'
          : code != _second.text
              ? 'The two codes are different.'
              : null;
    });
    if (_error == null) Navigator.of(context).pop(code);
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        counterText: '',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      );

  @override
  Widget build(BuildContext context) {
    TextField field(TextEditingController c, String label, {bool last = false}) => TextField(
          controller: c,
          decoration: _decoration(label),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 6,
          obscureText: true,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, letterSpacing: 8),
          onSubmitted: last ? (_) => _save() : null,
        );
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      icon: const Icon(Icons.password_rounded, size: 36, color: kPurple),
      title: const Text('New parent code', textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '4 to 6 digits. It changes on every device of the family.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          field(_first, 'New code'),
          const SizedBox(height: 12),
          field(_second, 'Again', last: true),
          SizedBox(
            height: 28,
            child: Center(
              child: Text(
                _error ?? '',
                style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kPurple),
          onPressed: _save,
          child: const Text('Change'),
        ),
      ],
    );
  }
}

/// Keypad to type the parent code. Returns the code once it is right
/// (wrong codes are refused inside the dialog), or null if cancelled.
class _CodeDialog extends StatefulWidget {
  const _CodeDialog({required this.expected});
  final String expected;

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  String _typed = '';
  bool _wrong = false;

  void _press(String digit) {
    final expected = widget.expected;
    if (_typed.length >= expected.length) return;
    HapticFeedback.selectionClick();
    setState(() {
      _wrong = false;
      _typed += digit;
    });
    if (_typed.length == expected.length) {
      if (_typed == expected) {
        Navigator.of(context).pop(_typed);
      } else {
        HapticFeedback.heavyImpact();
        setState(() {
          _wrong = true;
          _typed = '';
        });
      }
    }
  }

  void _erase() {
    if (_typed.isEmpty) return;
    setState(() => _typed = _typed.substring(0, _typed.length - 1));
  }

  Widget _key(Widget child, VoidCallback onTap) => SizedBox(
        width: 72,
        height: 72,
        child: Material(
          color: kPurple.withValues(alpha: 0.1),
          shape: const CircleBorder(),
          child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: Center(child: child)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    const digitStyle = TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: kInk);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      icon: const Icon(Icons.lock_rounded, size: 36, color: kPurple),
      title: const Text('Parent code', textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // One dot per digit typed
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.expected.length; i++)
                Container(
                  width: 18,
                  height: 18,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _typed.length ? kPurple : Colors.transparent,
                    border: Border.all(color: _wrong ? Colors.redAccent : kPurple, width: 2),
                  ),
                ),
            ],
          ),
          SizedBox(
            height: 28,
            child: Center(
              child: Text(
                _wrong ? 'Wrong code' : '',
                style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          for (final row in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [for (final d in row) _key(Text(d, style: digitStyle), () => _press(d))],
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const SizedBox(width: 72),
              _key(const Text('0', style: digitStyle), () => _press('0')),
              _key(const Icon(Icons.backspace_outlined, color: kInk), _erase),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      ],
    );
  }
}

/// Banner shown while parent mode is on: time left, and a button to lock now.
class ParentBanner extends StatelessWidget {
  const ParentBanner({super.key, required this.lock});
  final ParentLock lock;

  @override
  Widget build(BuildContext context) {
    final s = lock.remaining.inSeconds;
    final left = '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    return Center(
      child: ActionChip(
        avatar: const Icon(Icons.lock_open_rounded, color: Colors.white, size: 18),
        backgroundColor: kPurple,
        side: BorderSide.none,
        label: Text(
          'Parent mode · $left · Lock',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        onPressed: lock.lock,
      ),
    );
  }
}
