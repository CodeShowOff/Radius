import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum DeviceLogLevel { debug, info, warning, error }

class DeviceLog {
  DeviceLog._();

  static final DeviceLog instance = DeviceLog._();

  static const int _maxFileBytes = 1024 * 1024; // 1 MB
  static const int _maxFilesToKeep = 5;

  final StreamController<void> _onChange = StreamController<void>.broadcast();

  File? _currentFile;
  IOSink? _sink;
  Future<void> _writeChain = Future<void>.value();
  bool _initialized = false;

  String _sessionId = _newSessionId();

  Stream<void> get onChange => _onChange.stream;

  String get sessionId => _sessionId;

  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    if (kIsWeb) {
      _initialized = true;
      return;
    }

    try {
      _sessionId = _newSessionId();
      await _openOrRotateFile();
      _initialized = true;

      info('app', 'DeviceLog initialized', data: {
        'sessionId': _sessionId,
        'platform': defaultTargetPlatform.name,
        'isRelease': kReleaseMode,
      });
    } catch (e) {
      // Never crash the app due to logging.
      _initialized = true;
    }
  }

  Future<Directory?> _logsDir() async {
    if (kIsWeb) return null;
    try {
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory('${base.path}${Platform.pathSeparator}radius_logs');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    } catch (_) {
      return null;
    }
  }

  Future<void> _openOrRotateFile() async {
    final dir = await _logsDir();
    if (dir == null) return;

    // Rotate if needed.
    if (_currentFile != null) {
      try {
        final len = await _currentFile!.length();
        if (len < _maxFileBytes) return;
      } catch (_) {
        // Fall through to reopening.
      }
    }

    await _sink?.flush();
    await _sink?.close();
    _sink = null;

    final now = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File(
      '${dir.path}${Platform.pathSeparator}radius_${now}_$_sessionId.log',
    );

    _currentFile = file;
    _sink = file.openWrite(mode: FileMode.append);

    // Cleanup old log files.
    await _deleteOldFiles(dir);
  }

  Future<void> _deleteOldFiles(Directory dir) async {
    try {
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.log'))
          .toList()
        ..sort((a, b) {
          final at = a.statSync().modified.millisecondsSinceEpoch;
          final bt = b.statSync().modified.millisecondsSinceEpoch;
          return bt.compareTo(at);
        });

      if (files.length <= _maxFilesToKeep) return;
      for (final f in files.skip(_maxFilesToKeep)) {
        try {
          await f.delete();
        } catch (_) {
          // ignore
        }
      }
    } catch (_) {
      // ignore
    }
  }

  void debug(
    String tag,
    String message, {
    Map<String, Object?>? data,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(DeviceLogLevel.debug, tag, message,
        data: data, error: error, stackTrace: stackTrace);
  }

  void info(
    String tag,
    String message, {
    Map<String, Object?>? data,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(DeviceLogLevel.info, tag, message,
        data: data, error: error, stackTrace: stackTrace);
  }

  void warning(
    String tag,
    String message, {
    Map<String, Object?>? data,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(DeviceLogLevel.warning, tag, message,
        data: data, error: error, stackTrace: stackTrace);
  }

  void error(
    String tag,
    String message, {
    Map<String, Object?>? data,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(DeviceLogLevel.error, tag, message,
        data: data, error: error, stackTrace: stackTrace);
  }

  void _log(
    DeviceLogLevel level,
    String tag,
    String message, {
    Map<String, Object?>? data,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!_initialized) return;
    if (kIsWeb) return;

    // Mirror to console in debug mode (helps during development).
    if (kDebugMode) {
      // ignore: avoid_print
      print('[${level.name}] $tag: $message');
    }

    _writeChain = _writeChain.then((_) async {
      try {
        await _openOrRotateFile();
        final sink = _sink;
        if (sink == null) return;

        final entry = <String, Object?>{
          'ts': DateTime.now().toIso8601String(),
          'lvl': level.name,
          'tag': tag,
          'msg': message,
          'session': _sessionId,
          if (data != null && data.isNotEmpty) 'data': data,
          if (error != null) 'error': error.toString(),
          if (stackTrace != null) 'stack': stackTrace.toString(),
        };

        sink.writeln(jsonEncode(entry));
        await sink.flush();
        _onChange.add(null);
      } catch (_) {
        // ignore
      }
    });
  }

  Future<File?> currentLogFile() async {
    if (kIsWeb) return null;
    await _openOrRotateFile();
    return _currentFile;
  }

  Future<List<File>> listLogFiles() async {
    final dir = await _logsDir();
    if (dir == null) return const [];

    try {
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.log'))
          .toList()
        ..sort((a, b) {
          final at = a.statSync().modified.millisecondsSinceEpoch;
          final bt = b.statSync().modified.millisecondsSinceEpoch;
          return bt.compareTo(at);
        });
      return files;
    } catch (_) {
      return const [];
    }
  }

  Future<String> readTail({int maxBytes = 200 * 1024}) async {
    final file = await currentLogFile();
    if (file == null) return '';

    try {
      final raf = await file.open();
      try {
        final len = await raf.length();
        final start = len > maxBytes ? len - maxBytes : 0;
        await raf.setPosition(start);
        final bytes = await raf.read(len - start);
        return utf8.decode(bytes, allowMalformed: true);
      } finally {
        await raf.close();
      }
    } catch (_) {
      return '';
    }
  }

  Future<void> clearAll() async {
    final dir = await _logsDir();
    if (dir == null) return;

    try {
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {
      // ignore
    }

    _sink = null;
    _currentFile = null;

    try {
      final files = await listLogFiles();
      for (final f in files) {
        try {
          await f.delete();
        } catch (_) {
          // ignore
        }
      }
    } catch (_) {
      // ignore
    }

    await _openOrRotateFile();
    _onChange.add(null);
  }

  Future<void> dispose() async {
    try {
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {
      // ignore
    }
    await _onChange.close();
  }

  static String _newSessionId() {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final rand = (micros ^ 0x9e3779b97f4a7c15).toRadixString(16);
    return rand.padLeft(16, '0');
  }
}
