import 'dart:async';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'debug_logger.dart';

class WakeWordService {
  WakeWordService._();
  static final WakeWordService instance = WakeWordService._();

  final _logger = DebugLogger();
  static const _channel = MethodChannel('arya.wake_word');

  bool _isRunning = false;
  double _threshold = 0.5;
  bool _initialized = false;

  bool get isRunning => _isRunning;
  double get threshold => _threshold;

  void Function()? onWakeWordDetected;
  void Function(double score)? onInferenceScore;

  final List<double> _testScores = [];

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final prefs = await SharedPreferences.getInstance();
    _isRunning = prefs.getBool('wake_word_enabled') ?? false;
    _threshold = prefs.getDouble('wake_word_threshold') ?? 0.3;

    _logger.log('WakeWordService', 'Initialized (was running=$_isRunning, threshold=$_threshold)');

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'wakeWordDetected') {
        _logger.log('WakeWordService', 'Wake word detected!');
        onWakeWordDetected?.call();
      } else if (call.method == 'inferenceScore') {
        final score = (call.arguments as num?)?.toDouble() ?? 0.0;
        _testScores.add(score);
        onInferenceScore?.call(score);
      } else if (call.method == 'nativeLog') {
        _logger.log('WakeWordDetector', '${call.arguments}');
      }
    });

    if (_isRunning) {
      _logger.log('WakeWordService', 'Auto-starting from saved preference');
      await start();
    }
  }

  Future<void> start() async {
    try {
      _logger.log('WakeWordService', 'Starting (threshold=$_threshold)');
      await _channel.invokeMethod('start', {
        'threshold': _threshold,
      });
      _isRunning = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('wake_word_enabled', true);
      _logger.log('WakeWordService', 'Started successfully');
    } catch (e) {
      _logger.error('WakeWordService', 'Failed to start', e);
    }
  }

  void stop() {
    try {
      _logger.log('WakeWordService', 'Stopping');
      _channel.invokeMethod('stop');
    } catch (e) {
      _logger.error('WakeWordService', 'Failed to stop', e);
    }
    _isRunning = false;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('wake_word_enabled', false);
    });
    _logger.log('WakeWordService', 'Stopped');
  }

  void setThreshold(double value) {
    _threshold = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setDouble('wake_word_threshold', value);
    });
    if (_isRunning) {
      try {
        _channel.invokeMethod('setThreshold', {
          'threshold': value,
        });
      } catch (e) {
        _logger.error('WakeWordService', 'Failed to set threshold', e);
      }
    }
  }

  Future<double> runTest({int durationSeconds = 5}) async {
    _testScores.clear();

    if (!_isRunning) {
      try {
        _logger.log('WakeWordService', 'Starting for test');
        await _channel.invokeMethod('start', {
          'threshold': _threshold,
        });
      } catch (e) {
        _logger.error('WakeWordService', 'Failed to start test', e);
        return -1.0;
      }
    }

    // Set test mode AFTER start so sendScoresToDart isn't reset
    try {
      await _channel.invokeMethod('setTestMode', {'enabled': true});
    } catch (e) {
      _logger.error('WakeWordService', 'Failed to set test mode', e);
      return -1.0;
    }

    await Future.delayed(Duration(seconds: durationSeconds));

    if (_testScores.isEmpty) {
      _logger.log('WakeWordService', 'Test completed: no scores received');
    } else {
      final maxScore = _testScores.reduce((a, b) => a > b ? a : b);
      _logger.log('WakeWordService', 'Test completed: ${_testScores.length} scores, max=$maxScore');
    }

    try {
      await _channel.invokeMethod('setTestMode', {'enabled': false});
    } catch (e) {
      _logger.error('WakeWordService', 'Failed to disable test mode', e);
    }

    return _testScores.isEmpty ? -1.0 : _testScores.reduce((a, b) => a > b ? a : b);
  }
}
