import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DebugLogger {
  static final DebugLogger _instance = DebugLogger._();
  factory DebugLogger() => _instance;
  DebugLogger._();

  File? _logFile;
  bool _verboseEnabled = false;
  bool _initialized = false;

  bool get verboseEnabled => _verboseEnabled;

  Future<void> initialize() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _verboseEnabled = prefs.getBool('verbose_logging') ?? false;
    final dir = await getApplicationDocumentsDirectory();
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final mo = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final h = now.hour.toString().padLeft(2, '0');
    final mi = now.minute.toString().padLeft(2, '0');
    final fileName = 'arya-debug.log.$y-$mo-$d-$h-$mi.txt';
    _logFile = File('${dir.path}/$fileName');
    await _logFile!.create(recursive: true);
    _initialized = true;
    log('DebugLogger', 'Logger initialized - arya version 1.0.0');
    if (_verboseEnabled) {
      verbose('DebugLogger', 'Verbose logging enabled');
    }
  }

  Future<void> setVerboseEnabled(bool enabled) async {
    _verboseEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('verbose_logging', enabled);
    log('DebugLogger', 'Verbose logging ${enabled ? "enabled" : "disabled"}');
  }

  void log(String tag, String message) {
    _writeToFile('[${_timestamp()}] [$tag] $message');
  }

  void verbose(String tag, String message) {
    if (!_verboseEnabled) return;
    _writeToFile('[${_timestamp()}] [$tag] [VERBOSE] $message');
  }

  void error(String tag, String message, [dynamic exception]) {
    final line = '[${_timestamp()}] [$tag] [ERROR] $message';
    _writeToFile(line);
    if (exception != null) {
      _writeToFile('[${_timestamp()}] [$tag] [ERROR] Exception: $exception');
    }
  }

  void _writeToFile(String line) {
    try {
      _logFile?.writeAsStringSync('$line\n', mode: FileMode.append);
    } catch (_) {}
    debugPrint(line);
  }

  String? getLogFilePath() {
    return _logFile?.path;
  }

  Future<void> deleteOldLogs() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final files = dir.listSync().whereType<File>().where(
        (f) => f.path.contains('arya-debug.log.'),
      );
      for (final f in files) {
        if (f.path != _logFile?.path) {
          await f.delete();
        }
      }
    } catch (_) {}
  }
}
