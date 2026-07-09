import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'debug_logger.dart';

class SettingsService {
  static const _channel = MethodChannel('arya.save_directory');
  static const _version = 1;

  // AES-256 key: SHA-256 of passphrase (32 bytes)
  static Uint8List _encryptionKey(String passphrase) {
    return Uint8List.fromList(sha256.convert(utf8.encode(passphrase)).bytes);
  }

  // HMAC key: SHA-256 of passphrase + salt (32 bytes)
  static Uint8List _hmacKey(String passphrase) {
    return Uint8List.fromList(
        sha256.convert(utf8.encode('$passphrase:arya-hmac')).bytes);
  }

  // AES-256-CBC encrypt then HMAC-SHA256.
  // Output format: base64(IV(16) + HMAC(32) + ciphertext)
  static String _encrypt(String plaintext, String passphrase) {
    DebugLogger().verbose('SettingsService', '_encrypt: plaintext length=${plaintext.length}');
    final start = DateTime.now();
    final key = enc.Key(_encryptionKey(passphrase));
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt(plaintext, iv: iv);
    // Encrypt-then-MAC: HMAC over the ciphertext
    final hmac = Hmac(sha256, _hmacKey(passphrase));
    final mac = hmac.convert(encrypted.bytes);
    final combined = Uint8List.fromList([...iv.bytes, ...mac.bytes, ...encrypted.bytes]);
    final result = base64.encode(combined);
    final elapsed = DateTime.now().difference(start).inMilliseconds;
    DebugLogger().verbose('SettingsService', '_encrypt done in ${elapsed}ms, output length=${result.length}');
    return result;
  }

  // Decrypt: verify HMAC, then AES-256-CBC decrypt.
  static String _decrypt(String encoded, String passphrase) {
    DebugLogger().verbose('SettingsService', '_decrypt: input length=${encoded.length}');
    final start = DateTime.now();
    final decoded = base64.decode(encoded);
    if (decoded.length < 49) {
      throw FormatException('Invalid encrypted data');
    }
    final iv = enc.IV(decoded.sublist(0, 16));
    final storedMac = decoded.sublist(16, 48);
    final ciphertext = decoded.sublist(48);
    // Verify HMAC first (encrypt-then-MAC)
    final hmac = Hmac(sha256, _hmacKey(passphrase));
    final computedMac = hmac.convert(ciphertext);
    if (!_bytesEqual(storedMac, computedMac.bytes)) {
      DebugLogger().error('SettingsService', 'HMAC mismatch - wrong passphrase or corrupt data');
      throw FormatException('Wrong passphrase or corrupt data');
    }
    final key = enc.Key(_encryptionKey(passphrase));
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final result = encrypter.decrypt(enc.Encrypted(ciphertext), iv: iv);
    final elapsed = DateTime.now().difference(start).inMilliseconds;
    DebugLogger().verbose('SettingsService', '_decrypt done in ${elapsed}ms, plaintext length=${result.length}');
    return result;
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
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
    DebugLogger().verbose('SettingsService', 'exportToFile: collecting settings');
    final settings = await collectAllSettings();
    DebugLogger().verbose('SettingsService', 'exportToFile: collected ${settings.length} settings');
    final json = const JsonEncoder.withIndent(null).convert(settings);
    DebugLogger().verbose('SettingsService', 'exportToFile: JSON length=${json.length}');
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
      final ok = result != null;
      DebugLogger().verbose('SettingsService', 'exportToFile: result=$ok channelResult=$result');
      return ok;
    } catch (e) {
      DebugLogger().error('SettingsService', 'exportToFile channel error', e);
      return false;
    }
  }

  static Future<Map<String, dynamic>?> importFromFile(String passphrase) async {
    try {
      final content = await _channel.invokeMethod<String>('openSettingsFile', {
        'mimeType': 'application/json',
      });
      if (content == null) {
        DebugLogger().verbose('SettingsService', 'importFromFile: cancelled by user');
        return null;
      }
      DebugLogger().verbose('SettingsService', 'importFromFile: got file content length=${content.length}');
      final parsed = json.decode(content) as Map<String, dynamic>;
      if (parsed['version'] != _version) {
        throw FormatException('Unsupported settings version');
      }
      final encrypted = parsed['data'] as String;
      DebugLogger().verbose('SettingsService', 'importFromFile: encrypted data length=${encrypted.length}');
      final jsonStr = _decrypt(encrypted, passphrase);
      final settings = json.decode(jsonStr) as Map<String, dynamic>;
      DebugLogger().verbose('SettingsService', 'importFromFile: decoded ${settings.length} settings');
      return settings;
    } catch (e) {
      DebugLogger().error('SettingsService', 'importFromFile error', e);
      rethrow;
    }
  }
}
