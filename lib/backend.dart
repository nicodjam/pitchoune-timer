import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'child.dart';

/// Where the children are stored. [ChildrenStore] only talks to this
/// interface, so the storage can be swapped: Firestore in the app, memory in
/// the tests.
abstract class ChildrenBackend {
  /// The full list of children, sent again after every change.
  Stream<List<Child>> watch();

  Future<void> add(Child child);
  Future<void> update(String id, Map<String, Object?> fields);

  /// Adds [delta] seconds (negative to remove) to a child's bank.
  Future<void> increment(String id, int delta);

  Future<void> remove(String id);
}

/// Cloud Firestore: `families/{familyId}/children/{childId}`.
///
/// Firestore keeps a local cache: writes are applied locally at once (and the
/// stream reflects them), then sent to the server when the network allows.
class FirestoreBackend implements ChildrenBackend {
  FirestoreBackend(FirebaseFirestore db, String familyId)
      : _children = db.collection('families').doc(familyId).collection('children');

  final CollectionReference<Map<String, dynamic>> _children;

  @override
  Stream<List<Child>> watch() => _children
      .snapshots()
      .map((snap) => [for (final doc in snap.docs) Child.fromMap(doc.id, doc.data())]);

  @override
  Future<void> add(Child child) async {
    await _children.add(child.toMap());
  }

  @override
  Future<void> update(String id, Map<String, Object?> fields) => _children.doc(id).update(fields);

  @override
  Future<void> increment(String id, int delta) =>
      _children.doc(id).update({'seconds': FieldValue.increment(delta)});

  @override
  Future<void> remove(String id) => _children.doc(id).delete();
}

/// In-memory storage, for the tests.
class MemoryBackend implements ChildrenBackend {
  final _items = <String, Map<String, Object?>>{};
  final _changes = StreamController<List<Child>>.broadcast(sync: true);
  int _nextId = 0;

  void _emit() => _changes.add([
        for (final e in _items.entries) Child.fromMap(e.key, Map<String, dynamic>.from(e.value)),
      ]);

  @override
  Stream<List<Child>> watch() {
    scheduleMicrotask(_emit); // first list, once the listener is attached
    return _changes.stream;
  }

  @override
  Future<void> add(Child child) async {
    _items['child${_nextId++}'] = child.toMap();
    _emit();
  }

  @override
  Future<void> update(String id, Map<String, Object?> fields) async {
    _items[id]?.addAll(fields);
    _emit();
  }

  @override
  Future<void> increment(String id, int delta) async {
    final item = _items[id];
    if (item == null) return;
    item['seconds'] = (item['seconds'] as int) + delta;
    _emit();
  }

  @override
  Future<void> remove(String id) async {
    _items.remove(id);
    _emit();
  }
}
