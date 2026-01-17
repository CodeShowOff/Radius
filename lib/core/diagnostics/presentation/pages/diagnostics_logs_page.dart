import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../services/logging/device_log.dart';

class DiagnosticsLogsPage extends StatefulWidget {
  const DiagnosticsLogsPage({super.key});

  @override
  State<DiagnosticsLogsPage> createState() => _DiagnosticsLogsPageState();
}

class _DiagnosticsLogsPageState extends State<DiagnosticsLogsPage> {
  late Future<void> _loadFuture;
  StreamSubscription<void>? _sub;

  String _tail = '';
  String? _path;

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
    _sub = DeviceLog.instance.onChange.listen((_) {
      // Keep it lightweight; refresh tail opportunistically.
      unawaited(_load());
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    await DeviceLog.instance.init();
    final file = await DeviceLog.instance.currentLogFile();
    final tail = await DeviceLog.instance.readTail();

    if (!mounted) return;
    setState(() {
      _path = file?.path;
      _tail = tail;
    });
  }

  Future<void> _share() async {
    final file = await DeviceLog.instance.currentLogFile();
    if (file == null) return;

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text:
            'Radius diagnostics logs (session ${DeviceLog.instance.sessionId})',
      ),
    );
  }

  Future<void> _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: _tail));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Log copied to clipboard')),
    );
  }

  Future<void> _clear() async {
    await DeviceLog.instance.clearAll();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logs cleared')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics Logs'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => unawaited(_load()),
          ),
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share),
            onPressed: _share,
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          final busy = snapshot.connectionState == ConnectionState.waiting;

          return Column(
            children: [
              if (_path != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    'Current log file: $_path',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _copyToClipboard,
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _clear,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Clear'),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: busy
                      ? const Center(child: CircularProgressIndicator())
                      : SingleChildScrollView(
                          child: SelectableText(
                            _tail.isEmpty
                                ? 'No logs yet. Reproduce the issue, then come back here.'
                                : _tail,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
