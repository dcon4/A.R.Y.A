import 'package:arya/app.dart';
import 'package:arya/services/background_service.dart';
import 'package:arya/services/debug_logger.dart';
import 'package:arya/services/wake_word_service.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DebugLogger().initialize();
  await BackgroundService.initialize();
  // If the service was enabled but Android killed the notification (e.g. after
  // granting notification permission), restart it so the notification reappears.
  if (BackgroundService.isRunning) {
    await BackgroundService.start();
  }
  await WakeWordService.instance.initialize();
  runApp(const MyApp());
}