import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:radius/core/services/bluetooth/ble_id_generator.dart';

void main() {
  group('BleIdGenerator.parseAnonymousIdFromManufacturerData', () {
    test('parses legacy ASCII hex payload', () {
      final data = Uint8List.fromList('A1B2C3D4E5F60708'.codeUnits);
      final parsed = BleIdGenerator.parseAnonymousIdFromManufacturerData(data);
      expect(parsed, 'A1B2C3D4E5F60708');
    });

    test('rejects packed bytes payload without magic', () {
      final packed = Uint8List.fromList(<int>[
        0xA1,
        0xB2,
        0xC3,
        0xD4,
        0xE5,
        0xF6,
        0x07,
        0x08,
      ]);
      final parsed =
          BleIdGenerator.parseAnonymousIdFromManufacturerData(packed);
      expect(parsed, isNull);
    });

    test('parses magic + packed bytes payload', () {
      final data = Uint8List.fromList(<int>[
        0x52,
        0x44,
        0x01,
        0xA1,
        0xB2,
        0xC3,
        0xD4,
        0xE5,
        0xF6,
        0x07,
        0x08,
      ]);
      final parsed = BleIdGenerator.parseAnonymousIdFromManufacturerData(data);
      expect(parsed, 'A1B2C3D4E5F60708');
    });

    test('parses companyId + magic + packed bytes payload (iOS variant)', () {
      final data = Uint8List.fromList(<int>[
        0xFF,
        0xFF,
        0x52,
        0x44,
        0x01,
        0xA1,
        0xB2,
        0xC3,
        0xD4,
        0xE5,
        0xF6,
        0x07,
        0x08,
      ]);
      final parsed = BleIdGenerator.parseAnonymousIdFromManufacturerData(data);
      expect(parsed, 'A1B2C3D4E5F60708');
    });
  });
}
