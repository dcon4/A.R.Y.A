import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SaveDirectoryPicker {
  static const _channel = MethodChannel('arya.save_directory');
  static const _prefsKey = 'save_tree_uri';

  static Future<String?> pickDirectory() async {
    try {
      final uri = await _channel.invokeMethod<String>('pickDirectory');
      if (uri != null && uri.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, uri);
      }
      return uri;
    } catch (e) {
      return null;
    }
  }

  static Future<String?> getSavedUri() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKey);
  }

  static Future<bool> writeFile(String fileName, String content) async {
    final uri = await getSavedUri();
    if (uri == null) return false;
    try {
      await _channel.invokeMethod('writeFile', {
        'uri': uri,
        'fileName': fileName,
        'content': content,
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<void> clearSavedUri() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
