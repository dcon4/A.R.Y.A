import 'package:arya/app.dart';
import 'package:arya/services/background_service.dart';
import 'package:arya/services/debug_logger.dart';
import 'package:arya/services/wake_word_service.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DebugLogger().initialize();
  await BackgroundService.initialize();
  await WakeWordService.instance.initialize();
  runApp(const MyApp());
}