import 'dart:async';

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
  static void Function()? _onToggleWebSearch;
  static void Function()? _onTriggerSecondOpinion;
  static void Function()? _onRotateProvider;
  static void Function()? _onRotateAnnounceMode;
  static void Function()? _onToggleTtsPause;
  static void Function(bool inCall)? _onCallStateChanged;
  static Timer? _callPollTimer;
  static bool _inCall = false;

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
      } else if (call.method == 'toggleWebSearch') {
        _onToggleWebSearch?.call();
      } else if (call.method == 'triggerSecondOpinion') {
        _onTriggerSecondOpinion?.call();
      } else if (call.method == 'rotateProvider') {
        _onRotateProvider?.call();
      } else if (call.method == 'rotateAnnounceMode') {
        _onRotateAnnounceMode?.call();
      } else if (call.method == 'toggleTtsPause') {
        _onToggleTtsPause?.call();
      }
    });

    _startCallPolling();
  }

  // Watches the phone's audio mode so ARYA stops talking while a call is
  // ringing or in progress, and picks up where it left off afterwards.
  // Reading the mode needs no permission, unlike listening for call state.
  static void _startCallPolling() {
    _callPollTimer?.cancel();
    _callPollTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final inCall = await getAudioMode() != 0;
      if (inCall == _inCall) return;
      _inCall = inCall;
      _onCallStateChanged?.call(inCall);
    });
  }

  static Future<int> getAudioMode() async {
    try {
      final mode = await _channel.invokeMethod<int>('getAudioMode');
      return mode ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Pushes the current speech-pause state to the native side so the
  /// notification can label its button "Pause Speech" or "Resume Speech".
  static Future<void> setTtsPausedState(bool paused) async {
    try {
      await _channel.invokeMethod('setTtsPaused', paused);
    } catch (_) {}
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

  static void setOnToggleWebSearchCallback(void Function() callback) {
    _onToggleWebSearch = callback;
  }

  static void setOnTriggerSecondOpinionCallback(void Function() callback) {
    _onTriggerSecondOpinion = callback;
  }

  static void setOnRotateProviderCallback(void Function() callback) {
    _onRotateProvider = callback;
  }

  static void setOnRotateAnnounceModeCallback(void Function() callback) {
    _onRotateAnnounceMode = callback;
  }

  static void setOnToggleTtsPauseCallback(void Function() callback) {
    _onToggleTtsPause = callback;
  }

  static void setOnCallStateChangedCallback(void Function(bool inCall) callback) {
    _onCallStateChanged = callback;
    // Hand over any call already in progress, so speech stays held across a
    // screen reload instead of resuming in the middle of the call.
    callback(_inCall);
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
