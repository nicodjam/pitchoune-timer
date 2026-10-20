import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Parent code that unlocks bank changes and the end-of-countdown exit.
const kParentCode = '728';

/// "Parent mode": unlocked by the parent code, it locks itself again after
/// [duration]. Screens listen to it to show or hide what only a parent may do.
class ParentLock extends ChangeNotifier {
  ParentLock({this.duration = const Duration(minutes: 2)});

  final Duration duration;
  DateTime? _until;
  Timer? _ticker;

  bool get unlocked => _until != null && DateTime.now().isBefore(_until!);

  /// Time left before parent mode locks itself, or zero when locked.
  Duration get remaining => unlocked ? _until!.difference(DateTime.now()) : Duration.zero;

  /// Checks a typed code; unlocks parent mode if it is right.
  bool tryUnlock(String code) {
    if (code != kParentCode) return false;
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
      builder: (_) => const _CodeDialog(),
    );
    return code != null && tryUnlock(code);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

/// Keypad to type the parent code. Returns the code once it is right
/// (wrong codes are refused inside the dialog), or null if cancelled.
class _CodeDialog extends StatefulWidget {
  const _CodeDialog();

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  String _typed = '';
  bool _wrong = false;

  void _press(String digit) {
    if (_typed.length >= kParentCode.length) return;
    HapticFeedback.selectionClick();
    setState(() {
      _wrong = false;
      _typed += digit;
    });
    if (_typed.length == kParentCode.length) {
      if (_typed == kParentCode) {
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
              for (var i = 0; i < kParentCode.length; i++)
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
