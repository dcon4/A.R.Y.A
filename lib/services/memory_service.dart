import 'dart:convert';
import 'dart:io';
import 'package:arya/models/memory_entry.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryService {
  MemoryService._();
  static final MemoryService instance = MemoryService._();

  static const int maxMemories = 1000;
  static const int recallLimit = 10;

  final List<MemoryEntry> _entries = [];
  bool _loaded = false;

  List<MemoryEntry> get entries => List.unmodifiable(_entries);
  int get count => _entries.length;
  bool get isFull => _entries.length >= maxMemories;

  Future<String> get _filePath async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/memories.json';
  }

  Future<void> load() async {
    if (_loaded) return;
    final path = await _filePath;
    final file = File(path);
    if (await file.exists()) {
      try {
        final text = await file.readAsString();
        final list = jsonDecode(text) as List<dynamic>;
        _entries.clear();
        for (final item in list) {
          _entries.add(MemoryEntry.fromJson(item as Map<String, dynamic>));
        }
      } catch (_) {}
    }
    _loaded = true;
  }

  Future<void> save() async {
    final path = await _filePath;
    final file = File(path);
    final text = jsonEncode(_entries.map((e) => e.toJson()).toList());
    await file.writeAsString(text);
  }

  Future<MemoryEntry> addEntry(String content, {String type = 'fact'}) async {
    await load();
    // Evict oldest non-promoted if full
    if (_entries.length >= maxMemories) {
      final oldest = _entries
          .where((e) => !e.isPromoted)
          .reduce((a, b) => a.timestamp.isBefore(b.timestamp) ? a : b);
      _entries.remove(oldest);
    }
    final entry = MemoryEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      type: type,
      content: content,
      timestamp: DateTime.now(),
    );
    _entries.add(entry);
    await save();
    return entry;
  }

  Future<void> forget(String id) async {
    await load();
    _entries.removeWhere((e) => e.id == id);
    await save();
  }

  Future<int> forgetByContent(String query) async {
    await load();
    final lower = query.toLowerCase();
    final before = _entries.length;
    _entries.removeWhere(
        (e) => e.content.toLowerCase().contains(lower));
    if (_entries.length < before) {
      await save();
    }
    return before - _entries.length;
  }

  Future<void> clearAll() async {
    _entries.clear();
    await save();
  }

  List<MemoryEntry> search(String query) {
    if (query.isEmpty) return [];
    final scored = <MapEntry<double, MemoryEntry>>[];
    for (final entry in _entries) {
      final score = entry.scoreAgainst(query).toDouble();
      if (score > 0) {
        scored.add(MapEntry(score, entry));
      }
    }
    scored.sort((a, b) => b.key.compareTo(a.key));
    return scored.take(recallLimit).map((e) => e.value).toList();
  }

  Future<void> promote(String id) async {
    await load();
    final entry = _entries.where((e) => e.id == id).firstOrNull;
    if (entry != null && !entry.isPromoted) {
      entry.isPromoted = true;
      await save();
    }
  }

  Future<void> incrementHitCount(String id) async {
    final entry = _entries.where((e) => e.id == id).firstOrNull;
    if (entry != null) {
      entry.hitCount++;
      await save();
    }
  }

  List<MemoryEntry> getAllPromoted() {
    return _entries.where((e) => e.isPromoted).toList();
  }

  String formatForPrompt(List<MemoryEntry> memories) {
    if (memories.isEmpty) return '';
    final buffer = StringBuffer();
    buffer.writeln('Relevant context from past conversations:');
    for (final m in memories) {
      buffer.writeln('- $m.content');
    }
    return buffer.toString();
  }
}
