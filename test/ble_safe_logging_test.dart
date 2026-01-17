import 'package:flutter_test/flutter_test.dart';

import 'package:radius/core/services/bluetooth/ble_safe_logging.dart';

void main() {
  test('redactBleLogData redacts anonymousId and addresses', () {
    final redacted = redactBleLogData({
      'anonymousId': 'abc123',
      'remoteId': 'AA:BB:CC:DD:EE:FF',
      'deviceAddress': '11:22:33:44:55:66',
      'ok': 1,
    });

    expect(redacted, isNotNull);
    expect(redacted!['anonymousId'], '<redacted>');
    expect(redacted['remoteId'], '<redacted>');
    expect(redacted['deviceAddress'], '<redacted>');
    expect(redacted['ok'], 1);
  });

  test('redactBleLogData redacts manufacturer payloads', () {
    final redacted = redactBleLogData({
      'manufacturerData': <int, List<int>>{
        0x1234: <int>[0, 1, 2, 3],
      },
      'mfgData': <int>[1, 2, 3],
    });

    expect(redacted!['manufacturerData'], '<redacted manufacturer map>');
    expect(redacted['mfgData'], '<redacted 3 bytes>');
  });

  test('redactBleLogData deep-redacts nested maps', () {
    final redacted = redactBleLogData({
      'nested': {
        'anonymousId': 'abc',
        'manufacturerPayload': <int>[1, 2],
        'keep': true,
      },
    });

    final nested = redacted!['nested'] as Map<String, Object?>;
    expect(nested['anonymousId'], '<redacted>');
    expect(nested['manufacturerPayload'], '<redacted 2 bytes>');
    expect(nested['keep'], true);
  });
}
