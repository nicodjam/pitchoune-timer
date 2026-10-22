// Renders the screenshots of the user guide (README.md) without any device:
// each screen is built with a demo family, drawn by the Flutter test engine,
// and saved as a PNG in doc/screenshots/ ("golden files").
//
//   tool/screenshots.sh --render
//   (= flutter test --update-goldens test_screenshots/)
//
// This folder is not test/: a plain `flutter test` (and tool/release.sh) does
// not run it, since the pictures depend on the fonts of the machine.
//
// What needs real hardware (camera, status bar, the tablet's apps) is taken on
// the tablet with tool/screenshots.sh.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitchoune_timer/backend.dart';
import 'package:pitchoune_timer/child.dart';
import 'package:pitchoune_timer/family.dart';
import 'package:pitchoune_timer/family_screen.dart';
import 'package:pitchoune_timer/home_screen.dart';
import 'package:pitchoune_timer/parent.dart';
import 'package:pitchoune_timer/settings.dart';
import 'package:pitchoune_timer/settings_screen.dart';
import 'package:pitchoune_timer/setup_screen.dart';
import 'package:pitchoune_timer/theme.dart';
import 'package:pitchoune_timer/timer_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Size of a screenshot: a phone-sized window (logical pixels), drawn at
/// 1.5 pixels per logical pixel → 600 × 1200 PNG files.
const _logicalSize = Size(400, 800);
const _pixelRatio = 1.5;

/// Demo family shown on the pictures (never real names).
const _demoFamily = 'ABCDEFGHJKMN';

// --- Fonts -------------------------------------------------------------------
// The test engine draws text with a placeholder font (black boxes) unless real
// fonts are loaded: Roboto from the Flutter SDK, the Material icons from the
// app's assets, and the system's colour emoji font for the avatars.

String? _flutterRoot() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && Directory(env).existsSync()) return env;
  // The test runner is <flutter>/bin/cache/artifacts/engine/<platform>/flutter_tester.
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    if (Directory('${dir.path}/bin/cache/artifacts/material_fonts').existsSync()) return dir.path;
    dir = dir.parent;
  }
  return null;
}

Future<void> _loadFont(String family, Iterable<Future<ByteData>> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(f);
  }
  await loader.load();
}

Future<ByteData> _fileBytes(String path) async =>
    ByteData.sublistView(await File(path).readAsBytes());

Future<void> _loadFonts() async {
  final root = _flutterRoot();
  if (root == null) {
    stderr.writeln('Flutter SDK not found: texts will be drawn as boxes (set FLUTTER_ROOT)');
  } else {
    final fonts = Directory('$root/bin/cache/artifacts/material_fonts')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('Roboto-') && f.path.endsWith('.ttf'))
        .map((f) => _fileBytes(f.path));
    await _loadFont('Roboto', fonts);
  }
  await _loadFont('MaterialIcons', [rootBundle.load('fonts/MaterialIcons-Regular.otf')]);
  // Symbols missing from Roboto (→, ✓…), found on a device in a system font.
  const symbols = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf';
  if (File(symbols).existsSync()) {
    await _loadFont('DejaVuSans', [_fileBytes(symbols)]);
  } else {
    stderr.writeln('$symbols not found (sudo apt install fonts-dejavu-core): some symbols missing');
  }
  const emoji = '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf';
  if (File(emoji).existsSync()) {
    await _loadFont('NotoColorEmoji', [_fileBytes(emoji)]);
  } else {
    stderr.writeln('$emoji not found (sudo apt install fonts-noto-color-emoji): no animal avatars');
  }
}

// --- Fake native side ----------------------------------------------------------

void _mockNativeCode() {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(const MethodChannel('pitchoune/screen'), (call) async {
    return switch (call.method) {
      'canNotify' => true,
      'isBatteryUnrestricted' => false, // shows one "Allow" button on the setup screen
      'isHome' => false,
      'appVersion' => '1.0.0+6',
      _ => null,
    };
  });
  messenger.setMockMethodCallHandler(const MethodChannel('pitchoune/alarm'), (call) async {
    return call.method == 'hasPermission' ? true : null;
  });
  // Vibrations of the end screen, wake lock…: nothing to do in a test.
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
}

/// Only [signedIn] is read by the family screen.
class _DemoFamilyService implements FamilyService {
  @override
  bool get signedIn => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// --- Demo data -----------------------------------------------------------------

class _Demo {
  _Demo(this.store, this.otherDevice);
  final ChildrenStore store; // this tablet
  final ChildrenStore otherDevice; // a parent's phone, sharing the same banks

  String idOf(String name) => store.children.firstWhere((c) => c.name == name).id;

  void dispose() {
    store.dispose();
    otherDevice.dispose();
  }
}

Future<_Demo> _demo(WidgetTester tester) async {
  late _Demo demo;
  await tester.runAsync(() async {
    final backend = MemoryBackend();
    final store = ChildrenStore(backend, deviceId: 'tablet');
    final phone = ChildrenStore(backend, deviceId: 'phone');
    await store.load();
    await phone.load();
    for (final (name, avatar, minutes) in [('Lea', '🦊', 45), ('Tom', '🐼', 65), ('Zoe', '🐸', 0)]) {
      await store.add(name, avatar);
      final id = store.children.firstWhere((c) => c.name == name).id;
      if (minutes > 0) await store.addMinutes(id, minutes);
    }
    demo = _Demo(store, phone);
  });
  return demo;
}

// --- Rendering -----------------------------------------------------------------

Widget _app(Widget home) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: kPurple,
        scaffoldBackgroundColor: kBackgroundTop,
        fontFamily: 'Roboto',
        fontFamilyFallback: const ['NotoColorEmoji', 'DejaVuSans'],
      ),
      home: home,
    );

Future<void> _show(WidgetTester tester, Widget home, {Size size = _logicalSize}) async {
  tester.view.physicalSize = size * _pixelRatio;
  tester.view.devicePixelRatio = _pixelRatio;
  addTearDown(tester.view.reset);
  // Tests draw shadows as solid black shapes by default: draw them for real.
  debugDisableShadows = false;
  await tester.pumpWidget(_app(home));
  await _settle(tester);
}

/// Lets futures, animations and the store's updates run for a moment (the
/// screens have endless animations, so pumpAndSettle would never return).
Future<void> _settle(WidgetTester tester, [Duration time = const Duration(milliseconds: 800)]) async {
  for (var t = Duration.zero; t < time; t += const Duration(milliseconds: 100)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _save(String name) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile('../doc/screenshots/$name.png'));

/// Closes the screen (stops its timers) before the test ends.
Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
  debugDisableShadows = true; // the test framework checks it is restored
}

// --- The screenshots -----------------------------------------------------------

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await _loadFonts();
  });
  setUp(_mockNativeCode);

  testWidgets('family', (tester) async {
    await _show(tester, FamilyScreen(family: _DemoFamilyService()));
    await _save('family');
    await _close(tester);
  });

  testWidgets('home and family-qr', (tester) async {
    final demo = await _demo(tester);
    // Tom's countdown runs on the phone: his card says so on this tablet.
    await tester.runAsync(() => demo.otherDevice
        .markRunning(demo.idOf('Tom'), DateTime.now().add(const Duration(minutes: 20))));
    final parent = ParentLock();
    await _show(
      tester,
      HomeScreen(
        store: demo.store,
        parent: parent,
        familyCode: FamilyService.format(_demoFamily),
        onLeaveFamily: () async {},
        onOpenSettings: () {},
      ),
    );
    await _save('home');

    await tester.tap(find.byTooltip('Family'));
    await _settle(tester);
    await _save('family-qr');

    await _close(tester);
    parent.dispose();
    demo.dispose();
  });

  testWidgets('parent-code', (tester) async {
    final demo = await _demo(tester);
    final parent = ParentLock();
    await _show(tester, HomeScreen(store: demo.store, parent: parent));
    await tester.tap(find.byIcon(Icons.lock_rounded).first);
    await _settle(tester);
    await _save('parent-code');
    await _close(tester);
    parent.dispose();
    demo.dispose();
  });

  testWidgets('choose', (tester) async {
    final demo = await _demo(tester);
    final parent = ParentLock();
    await _show(tester, TimerScreen(store: demo.store, childId: demo.idOf('Lea'), parent: parent));
    await _save('choose');
    await _close(tester);
    parent.dispose();
    demo.dispose();
  });

  testWidgets('running', (tester) async {
    final demo = await _demo(tester);
    final parent = ParentLock();
    final session = TimerSession(
      childId: demo.idOf('Lea'),
      end: DateTime.now().add(const Duration(minutes: 7, seconds: 42)),
      total: 15 * 60,
      balanceAtStart: 45 * 60,
    );
    await _show(
      tester,
      TimerScreen(store: demo.store, childId: session.childId, parent: parent, resume: session),
    );
    await _save('running');
    await _close(tester);
    parent.dispose();
    demo.dispose();
  });

  testWidgets('finished', (tester) async {
    final demo = await _demo(tester);
    final parent = ParentLock();
    // A countdown that has just ended: the end screen, with its confetti.
    final session = TimerSession(
      childId: demo.idOf('Tom'),
      end: DateTime.now().subtract(const Duration(seconds: 1)),
      total: 20 * 60,
      balanceAtStart: 65 * 60,
    );
    await _show(
      tester,
      TimerScreen(store: demo.store, childId: session.childId, parent: parent, resume: session),
    );
    await _settle(tester, const Duration(milliseconds: 600)); // confetti in the air
    await _save('finished');
    await _close(tester);
    parent.dispose();
    demo.dispose();
  });

  testWidgets('setup', (tester) async {
    // Taller window: the whole list fits.
    await _show(tester, const SetupScreen(childMode: true), size: const Size(400, 1000));
    await _save('setup');
    await _close(tester);
  });

  testWidgets('settings', (tester) async {
    final demo = await _demo(tester);
    final settings = DeviceSettings();
    await tester.runAsync(() async {
      await settings.load();
      await settings.setChildMode(demo.idOf('Lea'));
    });
    await _show(tester, SettingsScreen(settings: settings, store: demo.store));
    await _save('settings');
    await _close(tester);
    demo.dispose();
  });
}
