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
}
