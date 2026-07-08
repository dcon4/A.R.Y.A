import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const _channel = MethodChannel('arya.save_directory');
  static const _version = 1;

  static Uint8List _deriveKey(String passphrase) {
    return Uint8List.fromList(sha256.convert(utf8.encode(passphrase)).bytes);
  }

  static String _encrypt(String plaintext, String passphrase) {
    final key = enc.Key(_deriveKey(passphrase));
    final iv = enc.IV.fromSecureRandom(12);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
    final encrypted = encrypter.encrypt(plaintext, iv: iv);
    final combined = Uint8List.fromList([...iv.bytes, ...encrypted.bytes]);
    return base64.encode(combined);
  }

  static String _decrypt(String encoded, String passphrase) {
    final key = enc.Key(_deriveKey(passphrase));
    final decoded = base64.decode(encoded);
    if (decoded.length < 13) {
      throw FormatException('Invalid encrypted data');
    }
    final iv = enc.IV(decoded.sublist(0, 12));
    final ciphertext = decoded.sublist(12);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
    return encrypter.decrypt(enc.Encrypted(ciphertext), iv: iv);
  }

  static Future<Map<String, dynamic>> collectAllSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final all = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      if (key.startsWith('flutter.')) continue;
      final s = prefs.getString(key);
      if (s != null) { all[key] = s; continue; }
      final b = prefs.getBool(key);
      if (b != null) { all[key] = b; continue; }
      final i = prefs.getInt(key);
      if (i != null) { all[key] = i; continue; }
      final d = prefs.getDouble(key);
      if (d != null) { all[key] = d; continue; }
      final sl = prefs.getStringList(key);
      if (sl != null) { all[key] = sl; }
    }
    return all;
  }

  static Future<void> applyAllSettings(Map<String, dynamic> settings) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in settings.entries) {
      final key = entry.key;
      final val = entry.value;
      if (val is String) {
        await prefs.setString(key, val);
      } else if (val is bool) {
        await prefs.setBool(key, val);
      } else if (val is int) {
        await prefs.setInt(key, val);
      } else if (val is double) {
        await prefs.setDouble(key, val);
      }
    }
  }

  static Future<bool> exportToFile(String passphrase) async {
    final settings = await collectAllSettings();
    final json = const JsonEncoder.withIndent(null).convert(settings);
    final encrypted = _encrypt(json, passphrase);
    final payload = const JsonEncoder.withIndent(null).convert({
      'version': _version,
      'data': encrypted,
    });
    try {
      final result = await _channel.invokeMethod<String>('saveSettingsFile', {
        'content': payload,
        'mimeType': 'application/json',
        'fileName': 'arya-settings.arya',
      });
      return result != null;
    } catch (e) {
      return false;
    }
  }

  static Future<Map<String, dynamic>?> importFromFile(String passphrase) async {
    try {
      final content = await _channel.invokeMethod<String>('openSettingsFile', {
        'mimeType': 'application/json',
      });
      if (content == null) return null;
      final parsed = json.decode(content) as Map<String, dynamic>;
      if (parsed['version'] != _version) {
        throw FormatException('Unsupported settings version');
      }
      final encrypted = parsed['data'] as String;
      final jsonStr = _decrypt(encrypted, passphrase);
      final settings = json.decode(jsonStr) as Map<String, dynamic>;
      return settings;
    } catch (e) {
      rethrow;
    }
  }
}
