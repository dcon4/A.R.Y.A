import 'dart:io';
import 'package:path_provider/path_provider.dart';

class ConversationEntry {
  final String userQuery;
  final String aiResponse;
  final String model;
  final DateTime timestamp;

  ConversationEntry({
    required this.userQuery,
    required this.aiResponse,
    required this.model,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class ConversationService {
  final List<ConversationEntry> _entries = [];
  String? _currentFilePath;
  String? _subject;
  bool _autoSaveEnabled = true;

  List<ConversationEntry> get entries => List.unmodifiable(_entries);
  bool get hasEntries => _entries.isNotEmpty;
  bool get autoSaveEnabled => _autoSaveEnabled;
  set autoSaveEnabled(bool val) => _autoSaveEnabled = val;

  void addEntry(ConversationEntry entry) {
    _entries.add(entry);
  }

  String _formatTimestamp(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$y.$mo.$d.$h.$mi.$s';
  }

  String _formatDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$y-$mo-$d $h:$mi:$s';
  }

  String _sanitizeSubject(String subject) {
    final cleaned = subject.replaceAll(RegExp(r'[^\w\s-]'), '');
    final words = cleaned.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final truncated = words.take(5).join(' ');
    if (truncated.length > 60) return truncated.substring(0, 60);
    return truncated.isEmpty ? 'Conversation' : truncated;
  }

  Future<String> getDocumentsDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  String buildFileName(String subject, DateTime dt) {
    final ts = _formatTimestamp(dt);
    final safe = _sanitizeSubject(subject);
    return 'ARYA.$ts.$safe.txt';
  }

  String buildContent(String subject) {
    final firstModel =
        _entries.isNotEmpty ? _entries.first.model : 'unknown';
    final buffer = StringBuffer();
    buffer.writeln('Subject: $subject');
    buffer.writeln('Model: $firstModel');
    buffer.writeln('Date: ${_formatDateTime(DateTime.now())}');
    buffer.writeln('---');
    buffer.writeln('');

    for (final entry in _entries) {
      buffer.writeln('--- User ---');
      buffer.writeln(entry.userQuery);
      buffer.writeln('');
      buffer.writeln('--- ARYA (${entry.model}) ---');
      buffer.writeln(entry.aiResponse);
      buffer.writeln('');
    }

    return buffer.toString();
  }

  Future<String> saveToFile({
    required String subject,
    DateTime? timestamp,
  }) async {
    final dir = await getDocumentsDir();
    final ts = timestamp ?? DateTime.now();
    final fileName = buildFileName(subject, ts);
    final filePath = '${dir}/$fileName';
    final content = buildContent(subject);
    final file = File(filePath);
    await file.writeAsString(content);
    _currentFilePath = filePath;
    _subject = subject;
    return filePath;
  }

  Future<String> autoSave() async {
    if (_entries.isEmpty) return '';

    // If we already have a file for this session, append the latest entry
    if (_currentFilePath != null && File(_currentFilePath!).existsSync()) {
      final latest = _entries.last;
      return appendToFile(_currentFilePath!, latest);
    }

    // First save - create the file
    final firstQuery = _entries.first.userQuery;
    final subject = _sanitizeSubject(firstQuery);
    return saveToFile(subject: subject, timestamp: _entries.first.timestamp);
  }

  Future<String> appendToFile(String filePath, ConversationEntry entry) async {
    final file = File(filePath);
    final content = StringBuffer();
    content.writeln('--- User ---');
    content.writeln(entry.userQuery);
    content.writeln('');
    content.writeln('--- ARYA (${entry.model}) ---');
    content.writeln(entry.aiResponse);
    content.writeln('');
    await file.writeAsString(content.toString(), mode: FileMode.append);
    return filePath;
  }
}
