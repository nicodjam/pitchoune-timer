import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'alarm.dart';
import 'apps.dart';
import 'child.dart';
import 'effects.dart';
import 'parent.dart';
import 'permissions.dart';
import 'screen.dart';
import 'theme.dart';

/// choose → running ⇄ paused → finished → (take more) → running …
enum _Phase { choose, running, paused, finished }

/// Quick amounts offered before a countdown, in minutes.
const _chooseShortcuts = [5, 10, 15, 30];

/// Amounts offered when a countdown ends, in minutes.
const _moreShortcuts = [1, 5, 10];

/// Default amount proposed when the screen opens.
const _defaultChoice = 10 * 60;

/// Animated opening of the timer screen (zoom + fade).
Route<void> timerRoute(
  ChildrenStore store,
  String childId, {
  required ParentLock parent,
  TimerSession? resume,
}) {
  return PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 450),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (context, animation, secondaryAnimation) =>
        TimerScreen(store: store, childId: childId, parent: parent, resume: resume),
    transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween(begin: 0.6, end: 1.0)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutBack)),
        child: child,
      ),
    ),
  );
}

/// A child's countdown. The child's balance works like a bank account: each
/// countdown withdraws the amount the child picks, up to what is left.
class TimerScreen extends StatefulWidget {
  const TimerScreen({
    super.key,
    required this.store,
    required this.childId,
    required this.parent,
    this.resume,
    this.standalone = false,
    this.onOpenSettings,
  });
  final ChildrenStore store;
  final String childId;

  /// Lets a parent leave the end screen without the child's choice.
  final ParentLock parent;

  /// Interrupted countdown (app killed by Android) to resume.
  final TimerSession? resume;

  /// Child mode: this screen is the app's root. Instead of closing, it comes
  /// back to the "choose" phase, and offers the settings (parent code).
  final bool standalone;
  final VoidCallback? onOpenSettings;

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // The child as last received from the store: other devices may change it
  // (minutes added, name…) while this screen is open.
  late Child _lastChild;
  Child get _child => _lastChild = widget.store.byId(widget.childId) ?? _lastChild;

  _Phase _phase = _Phase.choose;

  int _chosen = 0; // seconds picked in the choose phase
  int _total = 0; // seconds withdrawn for the current countdown
  int _balanceAtStart = 0; // bank balance when the current countdown started
  Duration _remaining = Duration.zero; // left in the current countdown
  DateTime? _end; // absolute end time: stays accurate even in the background
  Timer? _timer;
  int _debited = 0; // seconds of the current countdown already taken from the bank

  int _burst = 0; // re-fires the confetti when the app comes back to the foreground
  bool _finishedUnseen = false; // the countdown ended while the app was hidden
  bool _returnAfterChoice = false; // go back to the previous app after "take more"
  bool _resumedAfterKill = false; // started by main() after Android killed the app
  bool _sleepAllowed = false; // the app may put the device to sleep
  bool _blocked = false; // the child must act before leaving the app
  bool _parentAway = false; // child mode: a parent unlocked the app to leave it
  bool _wentAway = false; // the app went to the background since then
  Timer? _sleepTicker; // refreshes the "going to sleep in N s" message

  // The avatar bounces during the countdown; the gauge "beats" in the last minute.
  late final AnimationController _bounce =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 600));

  int get _remainingSeconds => (_remaining.inMilliseconds / 1000).ceil();

  /// Current bank balance, as known by the store.
  int get _bank => _child.balance;

  /// Seconds of the current countdown already spent.
  int get _spent => _total - _remainingSeconds;

  bool get _counting => _phase == _Phase.running || _phase == _Phase.paused;

  /// This countdown withdraws everything left: the bank will be empty at the end.
  bool get _emptiesBank => _total >= _balanceAtStart;

  /// When the device goes to sleep, for a countdown that empties the bank.
  DateTime? get _sleepAt => _end?.add(Alarm.sleepDelay);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastChild = widget.store.byId(widget.childId)!;
    widget.store.addListener(_onStoreChanged);
    // May "Stop" put the tablet to sleep? (device administrator right)
    Screen.canSleep().then((ok) {
      if (mounted) setState(() => _sleepAllowed = ok);
    });

    final resume = widget.resume;
    if (resume == null) {
      _chosen = min(_defaultChoice, _bank);
      if (widget.standalone) {
        // Child mode: the child stays in the app until they start a countdown.
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          _hold();
          await checkPermissions(context); // the guard needs "Display over other apps"
        });
      }
      return;
    }

    // Resuming a countdown started before the app was killed.
    _total = resume.total;
    _balanceAtStart = resume.balanceAtStart;
    _debited = resume.debited;
    _end = resume.end;
    _remaining = resume.end.difference(DateTime.now());
    _phase = _Phase.running;
    if (_remaining <= Duration.zero) {
      // Ended while the app was dead: the alarm has just relaunched it.
      _resumedAfterKill = true;
      _remaining = Duration.zero;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _finish();
      });
    } else {
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
      _bounce.repeat(reverse: true);
      Screen.keepOn(true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.store.removeListener(_onStoreChanged);
    if (_blocked) Screen.setBlocked(false);
    _timer?.cancel();
    _sleepTicker?.cancel();
    Screen.keepOn(false);
    _bounce.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _wentAway = true;
    if (state == AppLifecycleState.resumed) {
      // Child mode: a parent left the app with the code; once the app is back
      // in front (the tablet was handed back to the child), hold again.
      if (_parentAway && _wentAway) _parentAway = false;
      _wentAway = false;
      if (widget.standalone && _phase == _Phase.choose) _hold();
      if (_phase == _Phase.running) _tick();
      // Brought back to the foreground by the alarm: show the party now.
      if (_phase == _Phase.finished && _finishedUnseen) {
        _finishedUnseen = false;
        setState(() => _burst++);
      }
    } else if (_counting) {
      _save();
    }
  }

  /// The bank changed (possibly on another device): refresh the display.
  void _onStoreChanged() {
    if (!mounted) return;
    setState(() {
      // In the choose phase, never offer more than what is left, and propose
      // an amount again once a parent has refilled an empty bank.
      if (_phase == _Phase.choose) {
        _chosen = _chosen == 0 ? min(_defaultChoice, _bank) : min(_chosen, _bank);
      }
    });
  }

  // --- Logic -----------------------------------------------------------------

  /// Takes the time spent since the last save out of the bank. Only the
  /// difference is sent, so that minutes added meanwhile on another device
  /// are kept.
  void _save() {
    final delta = _spent - _debited;
    if (delta <= 0) return;
    _debited += delta;
    widget.store.debit(_child.id, delta);
    final session = widget.store.session;
    if (session != null) widget.store.startSession(session.copyWith(debited: _debited));
  }

  /// Choose phase: change the amount by whole minutes, within the bank.
  void _adjust(int minutes) {
    final bank = _bank;
    setState(() => _chosen = (_chosen + minutes * 60).clamp(min(60, bank), bank));
  }

  /// "Start" in the choose phase. In child mode, nothing asked for the
  /// permissions before (no home screen): ask here.
  Future<void> _start() async {
    if (_child.runningElsewhere(widget.store.deviceId)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("${_child.name}'s timer is already running on another device."),
      ));
      return;
    }
    if (widget.standalone) await checkPermissions(context);
    if (mounted) _withdraw(_chosen);
  }

  /// Leaves a finished or stopped countdown: back to the home screen, or in
  /// child mode back to the choose phase.
  void _leave() {
    // The bank stays in whole minutes: a minute started but not finished is
    // given back (the time spent is rounded down, so the bank is rounded up).
    widget.store.refund(_child.id, _debited % 60);
    if (!widget.standalone) {
      Navigator.of(context).pop();
      return;
    }
    _sleepTicker?.cancel();
    _bounce.value = 0;
    _pulse.value = 0;
    setState(() {
      _phase = _Phase.choose;
      _total = 0;
      _debited = 0;
      _end = null;
      _remaining = Duration.zero;
      _chosen = min(_defaultChoice, _bank);
    });
    _hold(); // child mode: held again until the next countdown
  }

  /// Child mode, choose phase: a parent unlocks the app to leave it.
  Future<void> _parentUnlock() async {
    if (!await widget.parent.ensure(context) || !mounted) return;
    _parentAway = true;
    _release();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Unlocked: you can leave the app. It locks again when it comes back.'),
    ));
  }

  /// Withdraws [seconds] from the bank (at most what is left) and counts down.
  void _withdraw(int seconds) {
    final bank = _bank;
    final amount = min(seconds, bank);
    if (amount <= 0) return;
    _total = amount;
    _balanceAtStart = bank;
    _debited = 0;
    _remaining = Duration(seconds: amount);
    _run();
  }

  /// Starts (or resumes after a pause) the current countdown.
  void _run() {
    _release(); // resuming after a pause, or more time after the end
    _parentAway = false; // a parent's free pass ends with the next countdown
    _end = DateTime.now().add(_remaining);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
    _bounce.repeat(reverse: true);
    setState(() => _phase = _Phase.running);
    // No screen sleep while the countdown is visible.
    Screen.keepOn(true);
    // System alarm: will bring the app back to the foreground at the end time.
    widget.store.startSession(TimerSession(
      childId: _child.id,
      end: _end!,
      total: _total,
      balanceAtStart: _balanceAtStart,
      debited: _debited,
    ));
    Alarm.schedule(_end!, _child.name, thenSleep: _emptiesBank);
    // Time left shown in the status bar, outside the app too.
    Screen.showCountdown(_child.name, _end!);
    // Other devices show that this child's timer is in use.
    widget.store.markRunning(_child.id, _end!);
  }

  void _pause() {
    _timer?.cancel();
    _bounce.animateTo(0);
    _pulse.animateTo(0);
    _save();
    _cancelAlarm();
    Screen.keepOn(false);
    setState(() => _phase = _Phase.paused);
    // Paused: the child stays here until they resume, or stop (sleep).
    _hold();
  }

  void _cancelAlarm() {
    Alarm.cancel();
    Screen.hideCountdown();
    widget.store.stopSession();
    widget.store.clearRunning(_child.id);
  }

  void _tick() {
    final r = _end!.difference(DateTime.now());
    if (r <= Duration.zero) {
      _finish();
      return;
    }
    setState(() => _remaining = r);
    // Debit every 5 seconds, in case the app gets killed.
    if (_spent - _debited >= 5) _save();
    if (r.inSeconds < 60 && !_pulse.isAnimating) _pulse.repeat(reverse: true);
  }

  void _finish() {
    _timer?.cancel();
    _bounce.animateTo(0);
    _pulse.animateTo(0);
    final hidden = WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed;
    _finishedUnseen = hidden;
    // Brought forward by the alarm: after "take more", go back to the previous app.
    _returnAfterChoice = hidden || _resumedAfterKill;
    _resumedAfterKill = false;
    setState(() {
      _remaining = Duration.zero;
      _phase = _Phase.finished;
    });
    // The child stays on this screen until they choose: more time, or stop.
    _hold();
    _save();
    // The alarm is NOT cancelled: it is what brings the app back to the
    // front if the countdown ended in the background.
    widget.store.stopSession();
    widget.store.clearRunning(_child.id);
    Screen.hideCountdown();
    // Minutes added on another device during the countdown: no sleep after all.
    // (Checked a moment later, once the store reflects this device's debit.)
    if (_emptiesBank) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _bank > 0) Alarm.cancelSleep();
      });
    }
    Screen.keepOn(false);
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 350), HapticFeedback.heavyImpact);
    Future.delayed(const Duration(milliseconds: 700), HapticFeedback.heavyImpact);

    // Bank empty: the sleep alarm will lock the device; show the countdown to it.
    if (_emptiesBank && _sleepAllowed) {
      _sleepTicker = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || DateTime.now().isAfter(_sleepAt!)) t.cancel();
        if (mounted) setState(() {});
      });
    }
  }

  /// Keeps the child on this screen: no back, and leaving the app shows the
  /// guard window over the other apps (Guard.kt).
  void _hold() {
    if (_blocked || _parentAway) return;
    setState(() => _blocked = true);
    // Text of the window shown over the other apps if the child leaves.
    final (title, message) = switch (_phase) {
      _Phase.choose => ('Hi ${_child.name}!', 'Go back to Pitchoune Timer\nand start your countdown.'),
      _Phase.paused => ('Paused', 'Go back to Pitchoune Timer\nto resume or stop.'),
      _ => ("Time's up!", 'Go back to Pitchoune Timer\nto choose what to do next.'),
    };
    Screen.setBlocked(true, title: title, message: message);
  }

  /// This screen no longer holds the child.
  void _release() {
    if (!_blocked) return;
    setState(() => _blocked = false);
    Screen.setBlocked(false);
  }

  /// "Stop" (paused or end screen): the countdown is over, the tablet goes to
  /// sleep (if allowed) and the app goes back to the home screen.
  Future<void> _stop() async {
    _release();
    Alarm.cancelSleep(); // sleeping now: no need for the delayed one
    await Screen.sleepNow();
    if (mounted) _leave();
  }

  /// Paused or end screen: a parent may leave without the child's choice.
  Future<void> _parentExit() async {
    if (!await widget.parent.ensure(context) || !mounted) return;
    _release();
    _parentAway = widget.standalone; // in child mode, free until the app comes back
    _leave();
  }

  /// End screen: withdraw a little more, then hand the screen back to the app
  /// the child was using when the alarm brought Pitchoune Timer forward.
  void _takeMore(int seconds) {
    _release();
    _withdraw(seconds);
    if (_returnAfterChoice) {
      _returnAfterChoice = false;
      Screen.sendToBack();
    }
  }

  // --- Display ---------------------------------------------------------------

  String get _message => switch (_phase) {
        _Phase.choose => 'How much time, ${_child.name}?',
        _Phase.running when _remaining.inSeconds < 60 => 'One minute left!',
        _Phase.running => "Let's go!",
        _Phase.paused => 'Paused',
        _Phase.finished => "Time's up!",
      };

  String get _sleepMessage {
    final left = (_sleepAt!.difference(DateTime.now()).inMilliseconds / 1000).ceil();
    return left > 0 ? 'Sleep time in $left s 😴' : 'Sleep time 😴';
  }

  String get _bankLine => _bank > 0 ? 'In the bank: ${formatBalance(_bank)}' : 'The bank is empty';

  @override
  Widget build(BuildContext context) {
    final c = childColor(_child.colorIndex);
    final warning = _phase == _Phase.running && _remaining.inSeconds < 60;
    final gaugeColor = switch (_phase) {
      _Phase.finished => kPurple,
      _ when warning => kWarning,
      _ => c,
    };
    final progress = switch (_phase) {
      _Phase.choose => _bank == 0 ? 0.0 : _chosen / _bank,
      _Phase.finished => 0.0,
      _ => _total == 0 ? 0.0 : (_remaining.inMilliseconds / (_total * 1000)).clamp(0.0, 1.0),
    };
    final shown = _phase == _Phase.choose ? Duration(seconds: _chosen) : _remaining;

    return PopScope<Object?>(
      // Only before a countdown may the system back button leave this screen;
      // afterwards, the way out is Pause then Stop (or the parent code).
      canPop: _phase == _Phase.choose && !widget.standalone,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && _counting) {
          _timer?.cancel();
          _save();
          _cancelAlarm();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 700),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(c, Colors.white, 0.78)!,
                      Color.lerp(gaugeColor, Colors.white, 0.45)!,
                    ],
                  ),
                ),
              ),
            ),
            const Positioned.fill(child: BubbleBackground(color: Colors.white, count: 12)),
            SafeArea(
              child: Column(
                children: [
                  SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        if (_phase == _Phase.choose && !widget.standalone)
                          IconButton(
                            iconSize: 32,
                            color: kInk,
                            tooltip: 'Back',
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                        const Spacer(),
                        // Child mode: the settings, behind the parent code.
                        if (_phase == _Phase.choose && widget.onOpenSettings != null)
                          IconButton(
                            iconSize: 28,
                            color: kInk.withValues(alpha: 0.5),
                            tooltip: 'Settings (parent)',
                            onPressed: () async {
                              if (await widget.parent.ensure(context)) widget.onOpenSettings!();
                            },
                            icon: const Icon(Icons.settings_rounded),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, cons) {
                        final size = min(cons.maxWidth, cons.maxHeight) * 0.88;
                        return Center(
                          child: AnimatedBuilder(
                            animation: _pulse,
                            builder: (context, child) =>
                                Transform.scale(scale: 1 + _pulse.value * 0.04, child: child),
                            child: SizedBox.square(
                              dimension: size,
                              child: CustomPaint(
                                painter: _Gauge(progress, gaugeColor),
                                child: _gaugeCenter(size, shown),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                    child: Text(
                      _message,
                      key: ValueKey(_message),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: warning ? darken(kWarning) : kInk,
                      ),
                    ),
                  ),
                  if (_phase != _Phase.running)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _bankLine,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: darken(c)),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: switch (_phase) {
                      _Phase.choose => _chooseControls(c),
                      _Phase.finished => _finishedControls(c),
                      _Phase.paused => _pausedControls(c),
                      _Phase.running => Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            RoundButton(
                              icon: Icons.pause_rounded,
                              color: c,
                              size: 92,
                              label: 'Pause',
                              onPressed: _pause,
                            ),
                            // Child mode, where the app is the home screen:
                            // the child's apps are opened from here.
                            if (widget.standalone) ...[
                              const SizedBox(width: 32),
                              RoundButton(
                                icon: Icons.apps_rounded,
                                color: c,
                                size: 92,
                                label: 'My apps',
                                onPressed: () => showAppsSheet(context),
                              ),
                            ],
                          ],
                        ),
                    },
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
            Positioned.fill(
              child: ConfettiBurst(key: ValueKey(_burst), active: _phase == _Phase.finished),
            ),
          ],
        ),
      ),
    );
  }

  /// Before a countdown: pick how much to withdraw, then start.
  Widget _chooseControls(Color c) {
    final bank = _bank;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final m in _chooseShortcuts)
              if (m * 60 < bank)
                ChoiceChip(
                  label: Text('$m min'),
                  selected: _chosen == m * 60,
                  onSelected: (_) => setState(() => _chosen = m * 60),
                ),
            ChoiceChip(
              label: const Text('All'),
              selected: _chosen == bank,
              onSelected: (_) => setState(() => _chosen = bank),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            RoundButton(
              icon: Icons.remove_rounded,
              color: c,
              size: 60,
              repeat: true,
              label: 'One minute less',
              onPressed: _chosen > min(60, bank) ? () => _adjust(-1) : null,
            ),
            const SizedBox(width: 24),
            RoundButton(
              icon: Icons.play_arrow_rounded,
              color: c,
              size: 92,
              label: 'Start',
              onPressed: _chosen > 0 ? _start : null,
            ),
            const SizedBox(width: 24),
            RoundButton(
              icon: Icons.add_rounded,
              color: c,
              size: 60,
              repeat: true,
              label: 'One minute more',
              onPressed: _chosen < bank ? () => _adjust(1) : null,
            ),
          ],
        ),
        if (widget.standalone && _blocked) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _parentUnlock,
            style: TextButton.styleFrom(foregroundColor: kInk.withValues(alpha: 0.6)),
            icon: const Icon(Icons.lock_rounded, size: 16),
            label: const Text('Parent'),
          ),
        ],
        // A parent unlocked the app: let them reach the account's apps.
        if (widget.standalone && _parentAway) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => showAppsSheet(context),
            style: TextButton.styleFrom(foregroundColor: kInk.withValues(alpha: 0.7)),
            icon: const Icon(Icons.apps_rounded, size: 18),
            label: const Text('Apps (parent)'),
          ),
        ],
      ],
    );
  }

  /// After a countdown: take a little more from the bank, or stop.
  Widget _finishedControls(Color c) {
    final bank = _bank;
    // (seconds, label) records; "All" replaces any shortcut it would duplicate.
    final options = <(int, String)>[
      for (final m in _moreShortcuts)
        if (m * 60 < bank) (m * 60, '+$m min'),
      if (bank > 0) (bank, 'All (${formatBalance(bank)})'),
    ];

    ButtonStyle style(Color bg) => FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (options.isNotEmpty) ...[
          const Text(
            'Keep going?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kInk),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              for (final (seconds, label) in options)
                FilledButton(
                  style: style(c),
                  onPressed: () => _takeMore(seconds),
                  child: Text(label),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (options.isEmpty && _sleepAllowed && _sleepAt != null) ...[
          Text(
            _sleepMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kInk),
          ),
          const SizedBox(height: 16),
        ],
        ..._stopAndParent(),
      ],
    );
  }

  /// Paused: resume the countdown, or stop (the tablet goes to sleep).
  Widget _pausedControls(Color c) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RoundButton(
          icon: Icons.play_arrow_rounded,
          color: c,
          size: 92,
          label: 'Resume',
          onPressed: _run,
        ),
        const SizedBox(height: 16),
        ..._stopAndParent(),
      ],
    );
  }

  /// "Stop" and the discreet "Parent" exit, shared by the paused and end screens.
  List<Widget> _stopAndParent() => [
        FilledButton.icon(
          onPressed: _stop,
          style: FilledButton.styleFrom(
            backgroundColor: kPurple,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: const StadiumBorder(),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          icon: Icon(_sleepAllowed ? Icons.bedtime_rounded : Icons.stop_rounded),
          label: Text(_sleepAllowed ? 'Stop and sleep' : 'Stop'),
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: _parentExit,
          style: TextButton.styleFrom(foregroundColor: kInk.withValues(alpha: 0.6)),
          icon: const Icon(Icons.lock_rounded, size: 16),
          label: const Text('Parent'),
        ),
      ];

  Widget _gaugeCenter(double size, Duration shown) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _bounce,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, -size * 0.04 * Curves.easeOut.transform(_bounce.value)),
              child: child,
            ),
            child: Text(_child.avatar, style: TextStyle(fontSize: size * 0.2)),
          ),
          SizedBox(
            width: size * 0.6,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _child.name,
                style: TextStyle(fontSize: size * 0.08, fontWeight: FontWeight.w900, color: kInk),
              ),
            ),
          ),
          SizedBox(
            width: size * 0.62,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                formatCountdown(shown),
                style: TextStyle(
                  fontSize: size * 0.17,
                  fontWeight: FontWeight.w900,
                  color: kInk,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Circular gauge, with a glowing "pearl" at the tip of its arc.
class _Gauge extends CustomPainter {
  _Gauge(this.progress, this.color);
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final stroke = size.shortestSide * 0.075;
    final radius = size.shortestSide / 2 - stroke;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Center disc
    canvas.drawCircle(center, radius, Paint()..color = Colors.white.withValues(alpha: 0.88));

    // Track
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = color.withValues(alpha: 0.18),
    );

    // Ticks: one per "hour" of the dial
    final tick = Paint()..color = color.withValues(alpha: 0.35);
    for (var i = 0; i < 12; i++) {
      final a = i * pi / 6;
      canvas.drawCircle(center + Offset(cos(a), sin(a)) * (radius - stroke * 1.1), stroke * 0.12, tick);
    }

    if (progress <= 0) return;

    // Arc
    canvas.drawArc(
      rect,
      -pi / 2,
      2 * pi * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: [Color.lerp(color, Colors.white, 0.35)!, color],
          transform: const GradientRotation(-pi / 2),
        ).createShader(rect),
    );

    // Pearl at the tip of the arc
    final a = -pi / 2 + 2 * pi * progress;
    final pearl = center + Offset(cos(a), sin(a)) * radius;
    canvas.drawCircle(pearl, stroke * 0.72, Paint()..color = Colors.white);
    canvas.drawCircle(pearl, stroke * 0.45, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Gauge old) => old.progress != progress || old.color != color;
}
