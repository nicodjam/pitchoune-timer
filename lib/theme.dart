import 'package:flutter/material.dart';

// App-wide colors
const kPurple = Color(0xFF6C4BF4);
const kInk = Color(0xFF2B2350);
const kBackgroundTop = Color(0xFFFFF4D6);
const kBackgroundBottom = Color(0xFFFFDCEB);
const kWarning = Color(0xFFFF7A45);

// One "candy" color per child
const childColors = <Color>[
  Color(0xFFFF6B6B), // strawberry red
  Color(0xFF4D96FF), // sky blue
  Color(0xFF3DBE6B), // apple green
  Color(0xFFFFA62B), // orange
  Color(0xFFB980F0), // lilac
  Color(0xFFFF7EB3), // pink
  Color(0xFF1FB5A8), // turquoise
  Color(0xFFE0B000), // lemon yellow
];

// Avatars to choose from
const avatars = <String>[
  '🦊', '🐼', '🐸', '🦁', '🐰', '🐯', '🐨', '🐙',
  '🦄', '🐢', '🐶', '🐱', '🐵', '🦖', '🐳', '🐝',
];

Color childColor(int index) => childColors[index % childColors.length];

/// Darker shade of a color, readable on a white background.
Color darken(Color c) => Color.lerp(c, kInk, 0.35)!;

/// A child's balance, in whole minutes rounded up: "25 min", "1 h 05 min".
/// (4 min 07 s shows as "5 min".)
String formatBalance(int seconds) {
  if (seconds <= 0) return '0 min';
  final minutes = (seconds / 60).ceil();
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return h > 0 ? '$h h ${m.toString().padLeft(2, '0')} min' : '$m min';
}

/// Countdown display: "04:59" or "1:04:59".
/// Rounded up to the next second, so the child sees 00:01 until the very end.
String formatCountdown(Duration d) {
  final total = (d.inMilliseconds / 1000).ceil();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  String p(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${p(m)}:${p(s)}' : '${p(m)}:${p(s)}';
}


/// "1.0.0+4" (pubspec.yaml) → "1.0.0 (build 4)".
String formatVersion(String version) {
  final parts = version.split('+');
  return parts.length == 2 ? '${parts[0]} (build ${parts[1]})' : version;
}
