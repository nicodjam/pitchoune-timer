import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitchoune_timer/backend.dart';
import 'package:pitchoune_timer/child.dart';
import 'package:pitchoune_timer/family.dart';
import 'package:pitchoune_timer/home_screen.dart';
import 'package:pitchoune_timer/parent.dart';
import 'package:pitchoune_timer/settings.dart';
import 'package:pitchoune_timer/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A store backed by memory instead of Firestore.
Future<ChildrenStore> newStore({String deviceId = 'this-device'}) async {
  final store = ChildrenStore(MemoryBackend(), deviceId: deviceId);
  await store.load();
  return store;
}

void main() {
  test('formatVersion shows the build number', () {
    expect(formatVersion('1.0.0+4'), '1.0.0 (build 4)');
    expect(formatVersion('1.2.0'), '1.2.0');
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Formatting', () {
    test('formatBalance', () {
      expect(formatBalance(0), '0 min');
      expect(formatBalance(25 * 60), '25 min');
      expect(formatBalance(4 * 60 + 7), '5 min'); // rounded up to the minute
      expect(formatBalance(1), '1 min');
      expect(formatBalance(3600 + 5 * 60), '1 h 05 min');
    });

    test('formatCountdown rounds up to the next second', () {
      expect(formatCountdown(const Duration(milliseconds: 100)), '00:01');
      expect(formatCountdown(const Duration(minutes: 5)), '05:00');
      expect(formatCountdown(const Duration(hours: 1, seconds: 59)), '1:00:59');
    });
  });

  group('ChildrenStore', () {
    test('addMinutes never goes below zero', () async {
      final store = await newStore();
      await store.add('Alice', '🦊');
      final id = store.children.single.id;

      await store.addMinutes(id, 2);
      expect(store.children.single.balance, 120);

      await store.addMinutes(id, -5);
      expect(store.children.single.balance, 0);
    });

    test('a debit is relative, so deposits made meanwhile are kept', () async {
      final store = await newStore();
      await store.add('Bob', '🐼');
      final id = store.children.single.id;
      await store.addMinutes(id, 10); // 600 s

      await store.debit(id, 30); // a countdown spends 30 s…
      await store.addMinutes(id, 1); // …while a parent deposits 1 min
      expect(store.children.single.balance, 600 - 30 + 60);
    });

    test('a bank that went negative is shown as empty and refilled from zero', () async {
      final store = await newStore();
      await store.add('Chloe', '🐸');
      final id = store.children.single.id;
      await store.debit(id, 30); // e.g. two devices debiting at the same time
      expect(store.children.single.seconds, -30);
      expect(store.children.single.balance, 0);

      await store.addMinutes(id, 1);
      expect(store.children.single.balance, 60);
    });

    test('a timer running on another device is detected', () async {
      final store = await newStore(deviceId: 'tablet');
      await store.add('Dan', '🦁');
      final id = store.children.single.id;
      await store.markRunning(id, DateTime.now().add(const Duration(minutes: 5)));

      expect(store.children.single.runningElsewhere('tablet'), isFalse); // this device
      expect(store.children.single.runningElsewhere('phone'), isTrue); // another device

      await store.clearRunning(id);
      expect(store.children.single.runningElsewhere('phone'), isFalse);
    });
  });

  group('TimerSession', () {
    test('survives a JSON round trip', () {
      final s = TimerSession(
        childId: 'a',
        end: DateTime.fromMillisecondsSinceEpoch(1000),
        total: 300,
        balanceAtStart: 1200,
        debited: 45,
      );
      final copy = TimerSession.fromJson(s.toJson());
      expect(copy.childId, 'a');
      expect(copy.end, s.end);
      expect(copy.total, 300);
      expect(copy.balanceAtStart, 1200);
      expect(copy.debited, 45);
    });

    test('older sessions still load', () {
      final s = TimerSession.fromJson({'childId': 'a', 'end': 0, 'total': 300});
      expect(s.balanceAtStart, 300);
      expect(s.debited, 0);
    });
  });

  group('Family code', () {
    test('is 12 unambiguous characters', () {
      final code = FamilyService.newCode();
      expect(code.length, FamilyService.codeLength);
      expect(code, isNot(matches(RegExp('[01OI]'))));
    });

    test('accepts what a person types', () {
      expect(FamilyService.normalize(' abcd-efgh jklm '), 'ABCDEFGHJKLM');
      expect(FamilyService.format('ABCDEFGHJKLM'), 'ABCD-EFGH-JKLM');
    });
  });

  group('ParentLock', () {
    test('only the parent code unlocks', () {
      final lock = ParentLock();
      expect(lock.tryUnlock('123'), isFalse);
      expect(lock.unlocked, isFalse);
      expect(lock.tryUnlock(kParentCode), isTrue);
      expect(lock.unlocked, isTrue);
      lock.lock();
      expect(lock.unlocked, isFalse);
      lock.dispose();
    });

    test('locks itself again after its duration', () async {
      final lock = ParentLock(duration: const Duration(milliseconds: 50));
      lock.tryUnlock(kParentCode);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(lock.unlocked, isFalse);
      lock.dispose();
    });
  });

  group('DeviceSettings', () {
    test('parent mode by default', () async {
      final settings = DeviceSettings();
      await settings.load();
      expect(settings.mode, DeviceMode.parent);
      expect(settings.childMode, isFalse);
    });

    test('child mode and its child are remembered on this device', () async {
      final settings = DeviceSettings();
      await settings.load();
      await settings.setChildMode('child42');

      final reloaded = DeviceSettings();
      await reloaded.load();
      expect(reloaded.childMode, isTrue);
      expect(reloaded.childId, 'child42');

      await reloaded.setParentMode();
      final again = DeviceSettings();
      await again.load();
      expect(again.childMode, isFalse);
    });
  });

  testWidgets('Home screen shows the empty state', (tester) async {
    final store = await newStore();
    final parent = ParentLock();
    await tester.pumpWidget(MaterialApp(home: HomeScreen(store: store, parent: parent)));
    await tester.pump();
    expect(find.text('No children yet'), findsOneWidget);
    parent.dispose();
  });

  testWidgets('Bank buttons are locked until the parent code is typed', (tester) async {
    final store = await newStore();
    await store.add('Emma', '🐰');
    final parent = ParentLock();
    await tester.pumpWidget(MaterialApp(home: HomeScreen(store: store, parent: parent)));
    await tester.pump();
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsNothing);

    parent.tryUnlock(kParentCode);
    await tester.pump();
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);

    parent.lock(); // stops the 1-second ticker before the test ends
    parent.dispose();
  });
}
