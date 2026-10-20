import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// An app of this tablet account, as listed by Apps.kt.
class LaunchableApp {
  const LaunchableApp(this.label, this.packageName, this.icon);
  final String label;
  final String packageName;
  final Uint8List icon; // PNG
}

/// Child mode, where Pitchoune Timer is the home screen: the account's apps,
/// opened from here instead of the usual launcher.
class Apps {
  static const _channel = MethodChannel('pitchoune/screen');

  static bool get available => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static List<LaunchableApp>? _cache;

  /// The account's apps, sorted by name (read once per launch).
  static Future<List<LaunchableApp>> list({bool refresh = false}) async {
    if (!available) return const [];
    if (_cache != null && !refresh) return _cache!;
    try {
      final raw = await _channel.invokeListMethod<Map<Object?, Object?>>('listApps') ?? const [];
      return _cache = [
        for (final m in raw)
          LaunchableApp(m['label']! as String, m['package']! as String, m['icon']! as Uint8List),
      ];
    } catch (e) {
      debugPrint('Apps.list: $e');
      return const [];
    }
  }

  static Future<bool> launch(String packageName) async {
    try {
      return await _channel.invokeMethod<bool>('launchApp', {'package': packageName}) ?? false;
    } catch (e) {
      debugPrint('Apps.launch: $e');
      return false;
    }
  }
}

/// Bottom sheet with the account's apps; a tap opens one.
Future<void> showAppsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.6,
      child: FutureBuilder<List<LaunchableApp>>(
        future: Apps.list(),
        builder: (context, snapshot) {
          final apps = snapshot.data;
          if (apps == null) return const Center(child: CircularProgressIndicator());
          if (apps.isEmpty) {
            return const Center(child: Text('No app to open', style: TextStyle(color: Colors.black54)));
          }
          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Text(
                  'My apps',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: kInk),
                ),
              ),
              Expanded(
                child: GridView.extent(
                  maxCrossAxisExtent: 120,
                  padding: const EdgeInsets.all(16),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  children: [
                    for (final app in apps)
                      InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          Navigator.of(context).pop();
                          Apps.launch(app.packageName);
                        },
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.memory(app.icon, width: 64, height: 64, gaplessPlayback: true),
                            const SizedBox(height: 6),
                            Text(
                              app.label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
