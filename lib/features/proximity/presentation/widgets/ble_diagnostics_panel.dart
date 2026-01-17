import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/services/bluetooth/ble_diagnostics.dart';

/// A collapsible diagnostics panel for BLE status
class BleDiagnosticsPanel extends StatefulWidget {
  const BleDiagnosticsPanel({super.key});

  @override
  State<BleDiagnosticsPanel> createState() => _BleDiagnosticsPanelState();
}

class _BleDiagnosticsPanelState extends State<BleDiagnosticsPanel> {
  final BleDiagnosticsService _diagnosticsService = BleDiagnosticsService();
  StreamSubscription<BleDiagnostics>? _subscription;
  BleDiagnostics _diagnostics = BleDiagnostics();
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _diagnostics = _diagnosticsService.currentDiagnostics;
    _subscription = _diagnosticsService.diagnosticsStream.listen((diag) {
      if (mounted) {
        setState(() => _diagnostics = diag);
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  String _formatTime(DateTime? time) {
    if (time == null) return 'Never';
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(25),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header - always visible
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.bug_report,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Diagnostics',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  // Quick status indicators
                  _StatusChip(
                    label: 'ADV',
                    isActive: _diagnostics.isAdvertising,
                    activeColor: Colors.green,
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(
                    label: 'SCAN',
                    isActive: _diagnostics.isScanning,
                    activeColor: Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Raw:${_diagnostics.rawDeviceCount} | Radius:${_diagnostics.parsedDeviceCount}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _isExpanded ? Icons.expand_more : Icons.expand_less,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),

          // Expanded content
          if (_isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status row
                  Row(
                    children: [
                      Expanded(
                        child: _DiagnosticItem(
                          icon: Icons.cell_tower,
                          label: 'Advertising',
                          value: _diagnostics.isAdvertising
                              ? 'Active'
                              : 'Inactive',
                          valueColor: _diagnostics.isAdvertising
                              ? Colors.green
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Expanded(
                        child: _DiagnosticItem(
                          icon: Icons.radar,
                          label: 'Scanning',
                          value:
                              _diagnostics.isScanning ? 'Active' : 'Inactive',
                          valueColor: _diagnostics.isScanning
                              ? Colors.blue
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Time row
                  Row(
                    children: [
                      Expanded(
                        child: _DiagnosticItem(
                          icon: Icons.access_time,
                          label: 'Last Advertise',
                          value: _formatTime(_diagnostics.lastAdvertiseTime),
                        ),
                      ),
                      Expanded(
                        child: _DiagnosticItem(
                          icon: Icons.access_time,
                          label: 'Last Scan',
                          value: _formatTime(_diagnostics.lastScanTime),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Device counts
                  Row(
                    children: [
                      Expanded(
                        child: _DiagnosticItem(
                          icon: Icons.bluetooth,
                          label: 'Raw BLE Devices',
                          value: '${_diagnostics.rawDeviceCount}',
                          valueColor: Colors.orange,
                        ),
                      ),
                      Expanded(
                        child: _DiagnosticItem(
                          icon: Icons.person_search,
                          label: 'Radius Devices',
                          value: '${_diagnostics.parsedDeviceCount}',
                          valueColor: Colors.green,
                        ),
                      ),
                    ],
                  ),

                  // Error display
                  if (_diagnostics.lastError != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 16,
                            color: colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _diagnostics.lastError!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Raw devices list (scrollable, limited height)
                  if (_diagnostics.rawDevices.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Nearby BLE Devices (${_diagnostics.rawDevices.length}):',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 120,
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: colorScheme.outlineVariant,
                        ),
                      ),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(4),
                        itemCount: _diagnostics.rawDevices.length,
                        itemBuilder: (context, index) {
                          final device = _diagnostics.rawDevices[index];
                          final hasRadiusUuid = device.serviceUuids.any(
                            (uuid) => uuid.toLowerCase().contains('beef'),
                          );
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Icon(
                                  hasRadiusUuid
                                      ? Icons.check_circle
                                      : Icons.bluetooth,
                                  size: 14,
                                  color: hasRadiusUuid
                                      ? Colors.green
                                      : colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    device.name.isEmpty
                                        ? device.deviceId.substring(0, 17)
                                        : device.name,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontFamily: 'monospace',
                                      fontSize: 10,
                                      color: hasRadiusUuid
                                          ? Colors.green
                                          : colorScheme.onSurface,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  '${device.rssi}dBm',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                    fontSize: 10,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color activeColor;

  const _StatusChip({
    required this.label,
    required this.isActive,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isActive ? activeColor.withAlpha(51) : Colors.grey.withAlpha(51),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isActive ? activeColor : Colors.grey,
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: isActive ? activeColor : Colors.grey,
        ),
      ),
    );
  }
}

class _DiagnosticItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _DiagnosticItem({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontSize: 9,
              ),
            ),
            Text(
              value,
              style: theme.textTheme.labelMedium?.copyWith(
                color: valueColor ?? colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ],
    );
  }
}
