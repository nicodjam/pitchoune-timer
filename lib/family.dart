import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The family this device belongs to.
///
/// Every device signs in **anonymously** (no account, no e-mail): Firebase
/// gives it a permanent id. A family is identified by a random **family code**,
/// typed once on each device. Knowing the code is what grants access, so it
/// must stay within the family (see firestore.rules).
class FamilyService extends ChangeNotifier {
  FamilyService(this._db, this._auth);

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  static const _familyKey = 'pitchoune.familyId';
  static const _legacyChildrenKey = 'pitchoune.children'; // before Firestore

  String? _familyId;

  /// Code of the family this device belongs to, or null if none yet.
  String? get familyId => _familyId;

  /// Anonymous user id of this device, or null if not signed in yet.
  String? get deviceId => _auth.currentUser?.uid;

  bool get signedIn => _auth.currentUser != null;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _familyId = prefs.getString(_familyKey);
    await signIn();
  }

  /// Anonymous sign-in. Needs the network the very first time only:
  /// Firebase then remembers the user on this device.
  Future<bool> signIn() async {
    if (_auth.currentUser != null) return true;
    try {
      // Without network the call may wait a long time: give up and let the
      // family screen offer to try again.
      await _auth.signInAnonymously().timeout(const Duration(seconds: 15));
      return true;
    } catch (e) {
      debugPrint('FamilyService.signIn: $e');
      return false;
    } finally {
      notifyListeners();
    }
  }

  // --- Family code -----------------------------------------------------------

  /// No 0/O or 1/I: easy to read aloud and to type.
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const codeLength = 12; // 32^12 ≈ 10^18 combinations

  static String newCode() {
    final r = Random.secure();
    return List.generate(codeLength, (_) => _alphabet[r.nextInt(_alphabet.length)]).join();
  }

  /// Text of the family QR code. The prefix makes sure a random QR code
  /// (a web link, a product) is never taken for a family.
  static const qrPrefix = 'pitchoune-family:';

  static String qrPayload(String id) => '$qrPrefix$id';

  /// The family code in a scanned QR code, or null if it is not one of ours.
  static String? codeFromQr(String? raw) {
    if (raw == null || !raw.startsWith(qrPrefix)) return null;
    final code = normalize(raw.substring(qrPrefix.length));
    if (code.length != codeLength) return null;
    if (code.split('').any((c) => !_alphabet.contains(c))) return null;
    return code;
  }

  /// "ABCDEFGHJKLM" → "ABCD-EFGH-JKLM"
  static String format(String code) =>
      [for (var i = 0; i < code.length; i += 4) code.substring(i, min(i + 4, code.length))].join('-');

  /// Accepts what a person types: lower case, spaces, dashes.
  static String normalize(String input) => input.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

  // --- Create / join / leave -------------------------------------------------

  DocumentReference<Map<String, dynamic>> _family(String id) => _db.collection('families').doc(id);

  /// Creates a new family, makes this device a member, and moves the children
  /// saved locally by older versions of the app into it. Needs the network.
  Future<void> create() async {
    final id = newCode();
    await _family(id).set({'createdAt': FieldValue.serverTimestamp()});
    await _becomeMember(id);
    await _importLocalChildren(id);
    await _remember(id);
  }

  /// Joins an existing family. Returns false if no family has this code.
  /// Needs the network.
  Future<bool> join(String input) async {
    final id = normalize(input);
    if (id.length != codeLength) return false;
    final snap = await _family(id).get();
    if (!snap.exists) return false;
    await _becomeMember(id);
    await _remember(id);
    return true;
  }

  /// This device leaves the family. The children stay in the family for the
  /// other devices.
  Future<void> leave() async {
    final id = _familyId;
    final uid = deviceId;
    if (id == null) return;
    if (uid != null) {
      try {
        await _family(id).collection('members').doc(uid).delete();
      } catch (e) {
        debugPrint('FamilyService.leave: $e');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_familyKey);
    _familyId = null;
    notifyListeners();
  }

  Future<void> _becomeMember(String id) =>
      _family(id).collection('members').doc(deviceId).set({'joinedAt': FieldValue.serverTimestamp()});

  Future<void> _remember(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_familyKey, id);
    _familyId = id;
    notifyListeners();
  }

  /// Older versions stored the children in SharedPreferences only.
  Future<void> _importLocalChildren(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_legacyChildrenKey);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final now = DateTime.now().millisecondsSinceEpoch;
      final batch = _db.batch();
      for (var i = 0; i < list.length; i++) {
        final m = list[i] as Map<String, dynamic>;
        batch.set(_family(id).collection('children').doc(), {
          'name': m['name'],
          'avatar': m['avatar'],
          'colorIndex': m['colorIndex'],
          'seconds': m['seconds'],
          'createdAt': now + i,
        });
      }
      await batch.commit();
      await prefs.remove(_legacyChildrenKey);
    } catch (e) {
      debugPrint('FamilyService._importLocalChildren: $e');
    }
  }
}
