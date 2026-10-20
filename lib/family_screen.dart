import 'package:flutter/material.dart';

import 'effects.dart';
import 'family.dart';
import 'theme.dart';

/// First screen on a new device: create a family, or join one with its code.
class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key, required this.family});
  final FamilyService family;

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  /// Runs a network action with a spinner and a readable error message.
  Future<void> _run(Future<String?> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      error = await action();
    } catch (e) {
      debugPrint('FamilyScreen: $e');
      error = 'Something went wrong. Check the internet connection and try again.';
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  Future<void> _create() => _run(() async {
        await widget.family.create();
        return null;
      });

  Future<void> _join() => _run(() async {
        final ok = await widget.family.join(_code.text);
        return ok ? null : 'No family has this code. Check it and try again.';
      });

  Future<void> _retrySignIn() => _run(() async {
        final ok = await widget.family.signIn();
        return ok ? null : 'No internet connection. The first launch needs one.';
      });

  @override
  Widget build(BuildContext context) {
    final signedIn = widget.family.signedIn;
    final codeLength = FamilyService.normalize(_code.text).length;

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
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const PitchouneTitle(),
                      const SizedBox(height: 8),
                      const Text(
                        'Share the time banks between all the family devices.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: kInk),
                      ),
                      const SizedBox(height: 24),
                      if (!signedIn)
                        _Panel(
                          title: 'No connection',
                          text: 'The first launch needs the internet, to give this device its id.',
                          child: FilledButton(
                            onPressed: _busy ? null : _retrySignIn,
                            style: FilledButton.styleFrom(backgroundColor: kPurple),
                            child: const Text('Try again'),
                          ),
                        )
                      else ...[
                        _Panel(
                          title: 'New family',
                          text: 'First device of the family? Create it, then type its code on the '
                              'other devices.',
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _create,
                            style: FilledButton.styleFrom(backgroundColor: kPurple),
                            icon: const Icon(Icons.add_home_rounded),
                            label: const Text('Create a family'),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _Panel(
                          title: 'Join a family',
                          text: 'Type the family code shown on a device that is already set up '
                              '(family button on the home screen).',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: _code,
                                enabled: !_busy,
                                textCapitalization: TextCapitalization.characters,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 2,
                                ),
                                onChanged: (_) => setState(() {}),
                                onSubmitted: (_) => _join(),
                                decoration: InputDecoration(
                                  hintText: 'ABCD-EFGH-JKLM',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                              ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed:
                                    _busy || codeLength != FamilyService.codeLength ? null : _join,
                                style: FilledButton.styleFrom(backgroundColor: kPurple),
                                icon: const Icon(Icons.group_add_rounded),
                                label: const Text('Join'),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_busy) ...[
                        const SizedBox(height: 24),
                        const Center(child: CircularProgressIndicator()),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.text, required this.child});
  final String title, text;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: kPurple, width: 3),
        boxShadow: [BoxShadow(color: kPurple.withValues(alpha: 0.35), offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: kInk)),
          const SizedBox(height: 6),
          Text(text, style: const TextStyle(fontSize: 15, color: Colors.black54)),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
