import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WakeWordService {
  WakeWordService._();
  static final WakeWordService instance = WakeWordService._();

  static const _channel = MethodChannel('arya.wake_word');

  bool _isRunning = false;
  double _threshold = 0.5;
  bool _initialized = false;

  bool get isRunning => _isRunning;
  double get threshold => _threshold;

  static void Function()? onWakeWordDetected;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final prefs = await SharedPreferences.getInstance();
    _isRunning = prefs.getBool('wake_word_enabled') ?? false;
    _threshold = prefs.getDouble('wake_word_threshold') ?? 0.5;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'wakeWordDetected') {
        onWakeWordDetected?.call();
      }
    });
  }

  Future<void> start() async {
    try {
      await _channel.invokeMethod('start', {
        'threshold': _threshold,
      });
      _isRunning = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('wake_word_enabled', true);
    } catch (e) {
      // Wake word may not be available on this device
    }
  }

  void stop() {
    try {
      _channel.invokeMethod('stop');
    } catch (_) {}
    _isRunning = false;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('wake_word_enabled', false);
    });
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
      } catch (_) {}
    }
  }
}
