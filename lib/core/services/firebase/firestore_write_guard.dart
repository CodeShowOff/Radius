import '../../error/exceptions.dart';

/// Blocks accidental persistence of sensitive BLE identifiers/payloads.
///
/// This is a client-side safety net. It does not replace Firestore security
/// rules, but it prevents common accidental writes from reaching the network.
class FirestoreWriteGuard {
  static const Set<String> _forbiddenKeys = <String>{
    // Raw BLE identifiers
    'bleId',
    'ble_id',
    'anonymousId',
    'bleAnonymousId',
    'currentAnonymousId',

    // Payloads / bytes
    'manufacturerData',
    'manufacturerPayload',
    'manufacturerPayloadFull',
    'mfgData',

    // Addresses
    'macAddress',
    'deviceAddress',
    'bluetoothAddress',
    'address',
    'remoteId',
  };

  static void assertSafe(Map<String, dynamic> data, {String? contextPath}) {
    final offenders = <String>[];
    _scan(data, path: '', offenders: offenders);

    if (offenders.isEmpty) return;

    final where = contextPath == null ? '' : ' at $contextPath';
    throw DatabaseException(
      message:
          'Blocked Firestore write$where: contains forbidden fields (${offenders.join(', ')}).',
      code: 'forbidden-field',
    );
  }

  static void _scan(
    Object? value, {
    required String path,
    required List<String> offenders,
  }) {
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString();
        final nextPath = path.isEmpty ? key : '$path.$key';

        if (_forbiddenKeys.contains(key)) {
          offenders.add(nextPath);
        }

        _scan(entry.value, path: nextPath, offenders: offenders);
      }
      return;
    }

    if (value is Iterable) {
      var index = 0;
      for (final item in value) {
        _scan(item, path: '$path[$index]', offenders: offenders);
        index++;
      }
    }
  }
}
