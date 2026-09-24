import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_write_guard.dart';

/// Batches Firestore writes to reduce costs and improve performance.
///
/// Instead of writing every update immediately, this batcher collects
/// writes and flushes them periodically or when the batch is full.
class FirestoreBatcher {
  final FirebaseFirestore _firestore;
  final Duration _flushInterval;
  final int _maxBatchSize;

  final Map<String, _PendingWrite> _pendingWrites = {};
  Timer? _flushTimer;
  bool _isFlushing = false;

  FirestoreBatcher({
    FirebaseFirestore? firestore,
    Duration flushInterval = const Duration(seconds: 5),
    int maxBatchSize = 50,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _flushInterval = flushInterval,
        _maxBatchSize = maxBatchSize;

  /// Queue a set operation.
  void set(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data, {
    SetOptions? options,
  }) {
    FirestoreWriteGuard.assertSafe(data, contextPath: ref.path);
    _pendingWrites[ref.path] = _PendingWrite(
      ref: ref,
      type: _WriteType.set,
      data: data,
      setOptions: options,
    );
    _scheduleFlush();
    _checkBatchSize();
  }

  /// Queue an update operation.
  void update(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data,
  ) {
    FirestoreWriteGuard.assertSafe(data, contextPath: ref.path);
    _pendingWrites[ref.path] = _PendingWrite(
      ref: ref,
      type: _WriteType.update,
      data: data,
    );
    _scheduleFlush();
    _checkBatchSize();
  }

  /// Queue a delete operation.
  void delete(DocumentReference<Map<String, dynamic>> ref) {
    _pendingWrites[ref.path] = _PendingWrite(
      ref: ref,
      type: _WriteType.delete,
    );
    _scheduleFlush();
    _checkBatchSize();
  }

  /// Force immediate flush.
  Future<void> flush() async {
    if (_isFlushing || _pendingWrites.isEmpty) return;

    _isFlushing = true;
    _flushTimer?.cancel();
    _flushTimer = null;

    try {
      final writes = Map<String, _PendingWrite>.from(_pendingWrites);
      _pendingWrites.clear();

      // Split into batches of 500 (Firestore limit)
      final entries = writes.entries.toList();
      for (var i = 0; i < entries.length; i += 500) {
        final batch = _firestore.batch();
        final batchEntries = entries.skip(i).take(500);

        for (final entry in batchEntries) {
          final write = entry.value;
          switch (write.type) {
            case _WriteType.set:
              if (write.setOptions != null) {
                batch.set(write.ref, write.data!, write.setOptions!);
              } else {
                batch.set(write.ref, write.data!);
              }
              break;
            case _WriteType.update:
              batch.update(write.ref, write.data!);
              break;
            case _WriteType.delete:
              batch.delete(write.ref);
              break;
          }
        }

        await batch.commit();
      }
    } finally {
      _isFlushing = false;
    }
  }

  void _scheduleFlush() {
    _flushTimer ??= Timer(_flushInterval, flush);
  }

  void _checkBatchSize() {
    if (_pendingWrites.length >= _maxBatchSize) {
      flush();
    }
  }

  /// Dispose the batcher, flushing any pending writes.
  Future<void> dispose() async {
    _flushTimer?.cancel();
    await flush();
  }
}

enum _WriteType { set, update, delete }

class _PendingWrite {
  final DocumentReference<Map<String, dynamic>> ref;
  final _WriteType type;
  final Map<String, dynamic>? data;
  final SetOptions? setOptions;

  _PendingWrite({
    required this.ref,
    required this.type,
    this.data,
    this.setOptions,
  });
}
