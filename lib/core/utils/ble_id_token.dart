import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Derives a non-reversible token from a rotating BLE identifier.
///
/// Purpose: avoid persisting raw BLE identifiers in Firestore.
///
/// This is NOT a secret HMAC (clients cannot safely hold a shared secret),
/// but it meaningfully reduces accidental leakage of raw identifiers.
class BleIdToken {
  static String tokenForBleId(String bleId) {
    final bytes = utf8.encode(bleId);
    return sha256.convert(bytes).toString();
  }
}
