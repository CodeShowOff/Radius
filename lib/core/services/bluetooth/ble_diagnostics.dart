import 'package:equatable/equatable.dart';

/// Snapshot of BLE discovery diagnostics.
///
/// This is best-effort debug data intended to help identify why discovery
/// might not be finding devices in the real world.
class BleDiagnosticsSnapshot extends Equatable {
  final bool isScanning;
  final bool isAdvertising;

  /// Last error seen by the Bluetooth service (may include advertiser errors).
  final String? lastError;

  /// Total scan result batches received.
  final int scanBatchCount;

  /// Total ScanResult items processed across batches.
  final int rawScanResultCount;

  /// Count of ScanResult items that contained our manufacturer ID key.
  final int msdMatchedCount;

  /// Count of Radius devices successfully parsed.
  final int parsedRadiusCount;

  /// Count filtered due to RSSI threshold.
  final int filteredByRssiCount;

  /// Count filtered due to invalid/missing manufacturer payload.
  final int filteredInvalidPayloadCount;

  const BleDiagnosticsSnapshot({
    required this.isScanning,
    required this.isAdvertising,
    required this.lastError,
    required this.scanBatchCount,
    required this.rawScanResultCount,
    required this.msdMatchedCount,
    required this.parsedRadiusCount,
    required this.filteredByRssiCount,
    required this.filteredInvalidPayloadCount,
  });

  int get filteredTotal => filteredByRssiCount + filteredInvalidPayloadCount;

  @override
  List<Object?> get props => [
        isScanning,
        isAdvertising,
        lastError,
        scanBatchCount,
        rawScanResultCount,
        msdMatchedCount,
        parsedRadiusCount,
        filteredByRssiCount,
        filteredInvalidPayloadCount,
      ];
}
