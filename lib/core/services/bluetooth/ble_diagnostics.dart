import 'package:equatable/equatable.dart';

/// Snapshot of BLE discovery diagnostics.
///
/// This is best-effort debug data intended to help identify why discovery
/// might not be finding devices in the real world.
class BleDiagnosticsSnapshot extends Equatable {
  final bool isScanning;
  final bool isAdvertising;

  /// Optional platform note for discovery reliability.
  ///
  /// This must not include raw identifiers.
  final String? platformDiscoveryNote;

  /// Last error seen by the Bluetooth service (may include advertiser errors).
  final String? lastError;

  /// Total scan result batches received.
  final int scanBatchCount;

  /// Total ScanResult items processed across batches.
  final int rawScanResultCount;

  /// Count of ScanResult items that contained our manufacturer ID key.
  final int msdMatchedCount;

  /// Count of ScanResult items that matched the Radius service UUID.
  final int serviceUuidMatchedCount;

  /// Total failed attempts to start scanning (permissions + runtime errors).
  final int scanStartFailures;

  /// Total failed attempts to start advertising (permissions + runtime errors).
  final int advertiseStartFailures;

  /// Permission denial counts keyed by operation/status.
  ///
  /// Example keys: `startScanning:denied`, `startAdvertising:permissionDeniedShowSettings`.
  final Map<String, int> permissionDeniedCounts;

  /// Best-effort timestamps (no identifiers).
  final DateTime? lastScanStartedAt;
  final DateTime? lastScanStoppedAt;
  final DateTime? lastAdvertiseStartedAt;
  final DateTime? lastAdvertiseStoppedAt;
  final DateTime? lastPermissionDeniedAt;

  /// Count of Radius devices successfully parsed.
  final int parsedRadiusCount;

  /// Count filtered due to RSSI threshold.
  final int filteredByRssiCount;

  /// Count filtered due to invalid/missing manufacturer payload.
  final int filteredInvalidPayloadCount;

  const BleDiagnosticsSnapshot({
    required this.isScanning,
    required this.isAdvertising,
    this.platformDiscoveryNote,
    required this.lastError,
    required this.scanBatchCount,
    required this.rawScanResultCount,
    required this.msdMatchedCount,
    required this.serviceUuidMatchedCount,
    required this.parsedRadiusCount,
    required this.filteredByRssiCount,
    required this.filteredInvalidPayloadCount,
    required this.scanStartFailures,
    required this.advertiseStartFailures,
    required this.permissionDeniedCounts,
    required this.lastScanStartedAt,
    required this.lastScanStoppedAt,
    required this.lastAdvertiseStartedAt,
    required this.lastAdvertiseStoppedAt,
    required this.lastPermissionDeniedAt,
  });

  int get filteredTotal => filteredByRssiCount + filteredInvalidPayloadCount;

  /// Backwards-compatible aliases with the naming used by the product request.
  int get scanMatchesByManufacturer => msdMatchedCount;
  int get scanMatchesByServiceUuid => serviceUuidMatchedCount;

  /// Safe diagnostics snapshot intended for UI/telemetry.
  ///
  /// This intentionally returns counts + timestamps only (no raw identifiers).
  Map<String, Object?> toSafeSnapshot() {
    String? ts(DateTime? d) => d?.toIso8601String();

    return <String, Object?>{
      'isScanning': isScanning,
      'isAdvertising': isAdvertising,
      if (platformDiscoveryNote != null)
        'platformDiscoveryNote': platformDiscoveryNote,
      'lastError': lastError,
      'scanBatchCount': scanBatchCount,
      'rawScanResultCount': rawScanResultCount,
      'scanMatchesByManufacturer': scanMatchesByManufacturer,
      'scanMatchesByServiceUuid': scanMatchesByServiceUuid,
      'parsedRadiusCount': parsedRadiusCount,
      'filteredByRssiCount': filteredByRssiCount,
      'filteredInvalidPayloadCount': filteredInvalidPayloadCount,
      'scanStartFailures': scanStartFailures,
      'advertiseStartFailures': advertiseStartFailures,
      'permissionDeniedCounts': permissionDeniedCounts,
      'lastScanStartedAt': ts(lastScanStartedAt),
      'lastScanStoppedAt': ts(lastScanStoppedAt),
      'lastAdvertiseStartedAt': ts(lastAdvertiseStartedAt),
      'lastAdvertiseStoppedAt': ts(lastAdvertiseStoppedAt),
      'lastPermissionDeniedAt': ts(lastPermissionDeniedAt),
    };
  }

  @override
  List<Object?> get props => [
        isScanning,
        isAdvertising,
        platformDiscoveryNote,
        lastError,
        scanBatchCount,
        rawScanResultCount,
        msdMatchedCount,
        serviceUuidMatchedCount,
        parsedRadiusCount,
        filteredByRssiCount,
        filteredInvalidPayloadCount,
        scanStartFailures,
        advertiseStartFailures,
        permissionDeniedCounts,
        lastScanStartedAt,
        lastScanStoppedAt,
        lastAdvertiseStartedAt,
        lastAdvertiseStoppedAt,
        lastPermissionDeniedAt,
      ];
}
