import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend.dart';
import 'theme.dart';

/// A child and their time bank, as stored in the backend.
///
/// Immutable: every change goes through the backend, which sends back a new
/// list of children. Shared by every device of the family.
class Child {
  const Child({
    required this.id,
    required this.name,
    required this.avatar,
    required this.colorIndex,
    this.seconds = 0,
    this.createdAt = 0,
    this.runningUntil,
    this.runningOn,
  });

  final String id;
  final String name;
  final String avatar;
  final int colorIndex; // index into childColors
  final int createdAt; // milliseconds since epoch, for a stable order

  /// Raw bank value. It can briefly go below zero when two devices change it
  /// at the same time; use [balance] for display and decisions.
  final int seconds;

  /// Set while a countdown is running for this child, on [runningOn].
  final DateTime? runningUntil;
  final String? runningOn; // id of the device running the countdown

  int get balance => max(0, seconds);

  /// A countdown for this child is running on another device right now.
  bool runningElsewhere(String deviceId) =>
      runningOn != null &&
      runningOn != deviceId &&
      runningUntil != null &&
      runningUntil!.isAfter(DateTime.now());

  Map<String, Object?> toMap() => {
        'name': name,
        'avatar': avatar,
        'colorIndex': colorIndex,
        'seconds': seconds,
        'createdAt': createdAt,
        'runningUntil': runningUntil?.millisecondsSinceEpoch,
        'runningOn': runningOn,
      };

  factory Child.fromMap(String id, Map<String, dynamic> m) {
    final until = (m['runningUntil'] as num?)?.toInt();
    return Child(
      id: id,
      name: m['name'] as String? ?? '?',
      avatar: m['avatar'] as String? ?? '🦊',
      colorIndex: (m['colorIndex'] as num?)?.toInt() ?? 0,
      seconds: (m['seconds'] as num?)?.toInt() ?? 0,
      createdAt: (m['createdAt'] as num?)?.toInt() ?? 0,
      runningUntil: until == null ? null : DateTime.fromMillisecondsSinceEpoch(until),
      runningOn: m['runningOn'] as String?,
    );
  }
}

/// A running countdown on this device: an amount withdrawn from the bank.
///
/// Stored locally only (not shared): it lets this device resume the countdown
/// if Android killed the process, and show the end screen when it comes back.
class TimerSession {
  TimerSession({
    required this.childId,
    required this.end,
    required this.total,
    required this.balanceAtStart,
    this.debited = 0,
  });

  final String childId;
  final DateTime end; // planned end time
  final int total; // seconds withdrawn for this countdown (for the gauge)
  final int balanceAtStart; // bank balance when the countdown started
  final int debited; // seconds of this countdown already taken from the bank

  TimerSession copyWith({int? debited}) => TimerSession(
        childId: childId,
        end: end,
        total: total,
        balanceAtStart: balanceAtStart,
        debited: debited ?? this.debited,
      );

  Map<String, dynamic> toJson() => {
        'childId': childId,
        'end': end.millisecondsSinceEpoch,
        'total': total,
        'balanceAtStart': balanceAtStart,
        'debited': debited,
      };

  factory TimerSession.fromJson(Map<String, dynamic> j) => TimerSession(
        childId: j['childId'] as String,
        end: DateTime.fromMillisecondsSinceEpoch(j['end'] as int),
        total: j['total'] as int,
        balanceAtStart: j['balanceAtStart'] as int? ?? j['total'] as int,
        debited: j['debited'] as int? ?? 0,
      );
}

/// The family's children, kept in sync with the backend.
///
/// Screens listen to it (ChangeNotifier) to refresh themselves. Every change
/// to a bank is sent as an **increment** (+60, −5…), never as a new absolute
/// value, so that changes made at the same time on two devices add up instead
/// of overwriting each other.
class ChildrenStore extends ChangeNotifier {
  ChildrenStore(this._backend, {required this.deviceId});

  final ChildrenBackend _backend;

  /// Identifies this device in [Child.runningOn].
  final String deviceId;

  static const _sessionKey = 'pitchoune.session';
  static const maxSeconds = 24 * 3600;

  List<Child> _children = const [];
  List<Child> get children => List.unmodifiable(_children);

  StreamSubscription<List<Child>>? _subscription;

  TimerSession? _session;
  TimerSession? get session => _session;

  /// Subscribes to the backend and waits for the first list of children
  /// (at most a few seconds, so that the app also starts offline).
  Future<void> load() async {
    final first = Completer<void>();
    _subscription = _backend.watch().listen(
      (list) {
        _children = [...list]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        notifyListeners();
        if (!first.isCompleted) first.complete();
      },
      onError: (Object e) {
        debugPrint('ChildrenStore: $e');
        if (!first.isCompleted) first.complete();
      },
    );
    await first.future.timeout(const Duration(seconds: 5), onTimeout: () {});

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionKey);
    if (raw != null) {
      try {
        final s = TimerSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (byId(s.childId) != null) _session = s;
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Child? byId(String id) {
    for (final c in _children) {
      if (c.id == id) return c;
    }
    return null;
  }

  // --- Children --------------------------------------------------------------

  Future<void> add(String name, String avatar) => _guard(_backend.add(Child(
        id: '',
        name: name,
        avatar: avatar,
        colorIndex: _freeColor(),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      )));

  Future<void> update(String id, String name, String avatar) =>
      _guard(_backend.update(id, {'name': name, 'avatar': avatar}));

  Future<void> remove(String id) => _guard(_backend.remove(id));

  // --- Bank ------------------------------------------------------------------

  /// Deposits (or removes, if negative) whole minutes, keeping the bank
  /// between 0 and [maxSeconds].
  Future<void> addMinutes(String id, int minutes) async {
    final c = byId(id);
    if (c == null) return;
    final target = (c.balance + minutes * 60).clamp(0, maxSeconds);
    final delta = target - c.seconds;
    if (delta == 0) return;
    await _guard(_backend.increment(id, delta));
  }

  /// Takes [seconds] out of the bank (time spent in a countdown).
  Future<void> debit(String id, int seconds) =>
      seconds <= 0 ? Future.value() : _guard(_backend.increment(id, -seconds));

  /// Gives [seconds] back to the bank.
  Future<void> refund(String id, int seconds) =>
      seconds <= 0 ? Future.value() : _guard(_backend.increment(id, seconds));

  Future<void> resetToZero(String id) => _guard(_backend.update(id, {'seconds': 0}));

  // --- Countdown shared state (seen by the other devices) --------------------

  Future<void> markRunning(String id, DateTime until) => _guard(_backend.update(id, {
        'runningUntil': until.millisecondsSinceEpoch,
        'runningOn': deviceId,
      }));

  Future<void> clearRunning(String id) =>
      _guard(_backend.update(id, {'runningUntil': null, 'runningOn': null}));

  // --- Countdown local state (this device only) ------------------------------

  Future<void> startSession(TimerSession s) async {
    _session = s;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, jsonEncode(s.toJson()));
  }

  Future<void> stopSession() async {
    _session = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }

  // --- Helpers ---------------------------------------------------------------

  /// Backend writes are not awaited by the UI (they may wait for the network);
  /// errors are only logged.
  Future<void> _guard(Future<void> write) =>
      write.catchError((Object e) => debugPrint('ChildrenStore write failed: $e'));

  /// Picks the least used color.
  int _freeColor() {
    final usage = List.filled(childColors.length, 0);
    for (final c in _children) {
      usage[c.colorIndex % childColors.length]++;
    }
    var best = 0;
    for (var i = 1; i < usage.length; i++) {
      if (usage[i] < usage[best]) best = i;
    }
    return best;
  }
}
