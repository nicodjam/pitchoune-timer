import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Who uses this tablet.
enum DeviceMode { parent, child }

/// Settings of **this tablet account** only, never shared with the family.
///
/// They live in SharedPreferences, which Android keeps per user profile: on a
/// tablet with a parent profile and a child profile, each profile has its own
/// settings. Only a parent may change them (parent code).
class DeviceSettings extends ChangeNotifier {
  static const _modeKey = 'pitchoune.mode';
  static const _childKey = 'pitchoune.childId';

  DeviceMode _mode = DeviceMode.parent;
  String? _childId;

  DeviceMode get mode => _mode;

  /// In child mode, the child this tablet account belongs to.
  String? get childId => _childId;

  bool get childMode => _mode == DeviceMode.child && _childId != null;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _mode = prefs.getString(_modeKey) == DeviceMode.child.name ? DeviceMode.child : DeviceMode.parent;
    _childId = prefs.getString(_childKey);
    notifyListeners();
  }

  Future<void> setParentMode() => _save(DeviceMode.parent, _childId);

  /// Child mode for [childId]: the app opens straight on this child's timer.
  Future<void> setChildMode(String childId) => _save(DeviceMode.child, childId);

  Future<void> _save(DeviceMode mode, String? childId) async {
    _mode = mode;
    _childId = childId;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode.name);
    if (childId == null) {
      await prefs.remove(_childKey);
    } else {
      await prefs.setString(_childKey, childId);
    }
  }
}
