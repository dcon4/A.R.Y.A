import 'package:arya/app.dart';
import 'package:arya/services/debug_logger.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DebugLogger().initialize();
  runApp(const MyApp());
}