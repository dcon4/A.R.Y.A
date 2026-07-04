import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BackgroundService {
  static const _channel = MethodChannel('arya.mic');
  static const _triggerChannel = MethodChannel('arya.mic_trigger');
  static bool _isRunning = false;
  static bool _initialized = false;
  static void Function()? _onStartMic;
  static void Function()? _onNewConversation;
  static void Function()? _onToggleBraveSearch;
  static void Function()? _onRotateProvider;

  static bool get isRunning => _isRunning;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final prefs = await SharedPreferences.getInstance();
    _isRunning = prefs.getBool('background_service') ?? false;

    _triggerChannel.setMethodCallHandler((call) async {
      if (call.method == 'startListening') {
        _onStartMic?.call();
      } else if (call.method == 'newConversation') {
        _onNewConversation?.call();
      } else if (call.method == 'toggleBraveSearch') {
        _onToggleBraveSearch?.call();
      } else if (call.method == 'rotateProvider') {
        _onRotateProvider?.call();
      }
    });
  }

  static void setOnStartMicCallback(void Function() callback) {
    _onStartMic = callback;
  }

  static void setOnNewConversationCallback(void Function() callback) {
    _onNewConversation = callback;
  }

  static void setOnToggleBraveSearchCallback(void Function() callback) {
    _onToggleBraveSearch = callback;
  }

  static void setOnRotateProviderCallback(void Function() callback) {
    _onRotateProvider = callback;
  }

  static Future<void> start() async {
    try {
      await _channel.invokeMethod('startForegroundService');
      _isRunning = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('background_service', true);
    } catch (e) {
      // Silently handle - service may not be available
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stopForegroundService');
    } catch (_) {}
    _isRunning = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('background_service', false);
  }

  static Future<void> setEnabled(bool enabled) async {
    if (enabled) {
      await start();
    } else {
      await stop();
    }
  }

  static Future<bool> getBluetoothEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('bluetooth_mic_control') ?? false;
  }

  static Future<void> setBluetoothEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bluetooth_mic_control', enabled);
  }
}
