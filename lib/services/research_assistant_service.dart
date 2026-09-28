import 'dart:async';
import 'dart:convert';

import 'package:arya/services/debug_logger.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class LocalSearchSource {
  final String file;
  final String folder;
  final String title;
  final String location;
  final double score;

  const LocalSearchSource({
    required this.file,
    required this.folder,
    required this.title,
    required this.location,
    required this.score,
  });
}

class LocalSearchResult {
  final bool ok;
  final String? answer;
  final String error;
  final List<LocalSearchSource> sources;
  final String model;

  const LocalSearchResult({
    required this.ok,
    this.answer,
    required this.error,
    required this.sources,
    required this.model,
  });
}

class ResearchAssistantService {
  static final ResearchAssistantService instance = ResearchAssistantService._();
  ResearchAssistantService._();

  static const String defaultAddress = 'http://192.168.0.210:8080/assistant';

  final _logger = DebugLogger();

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('local_search_enabled') ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('local_search_enabled', value);
  }

  static Future<String> getAddress() async {
    final prefs = await SharedPreferences.getInstance();
    var address = (prefs.getString('local_search_address') ?? '').trim();
    if (address.isEmpty) address = defaultAddress;
    if (!address.startsWith('http://') && !address.startsWith('https://')) {
      address = 'http://$address';
    }
    while (address.endsWith('/')) {
      address = address.substring(0, address.length - 1);
    }
    return address;
  }

  static Future<void> setAddress(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('local_search_address', value.trim());
  }

  static Future<String> getModel() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString('local_search_model') ?? '').trim();
  }

  static Future<void> setModel(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('local_search_model', value.trim());
  }

  Future<bool> checkReachable() async {
    try {
      final address = await getAddress();
      final response = await http
          .get(Uri.parse('$address/api/status'))
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body);
      return data['ok'] == true;
    } catch (e) {
      _logger.log('LocalSearch', 'Status check failed: $e');
      return false;
    }
  }

  Future<LocalSearchResult> ask(String question) async {
    final address = await getAddress();
    final model = await getModel();
    _logger.log(
        'LocalSearch', 'Ask "${question.length > 60 ? question.substring(0, 60) : question}" model=${model.isEmpty ? 'server default' : model}');

    try {
      final body = <String, dynamic>{'question': question};
      if (model.isNotEmpty) body['model'] = model;

      final response = await http
          .post(
            Uri.parse('$address/api/ask'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 120));

      if (response.statusCode == 400) {
        return _failure('The question was empty.', <LocalSearchSource>[]);
      }
      if (response.statusCode != 200) {
        return _failure(
            'The computer answered with an error.', <LocalSearchSource>[]);
      }

      final data = jsonDecode(response.body);
      final sources = _parseSources(data['sources']);
      final servedModel = (data['model'] ?? '').toString();
      _logger.log('LocalSearch',
          'Answer ok=${data['ok'] == true} sources=${sources.length} model=$servedModel');

      if (data['ok'] != true) {
        var error = (data['error'] ?? '').toString();
        if (error.isEmpty) error = 'The search could not be answered.';
        if (error.toLowerCase().contains('api key')) {
          error = 'The Research Assistant has no OpenRouter API key. Open '
              'its settings on the computer and paste the key.';
        }
        return LocalSearchResult(
          ok: false,
          answer: null,
          error: error,
          sources: sources,
          model: servedModel,
        );
      }

      final answer = (data['answer'] ?? '').toString();
      if (answer.trim().isEmpty) {
        return _failure('The computer returned an empty answer.', sources);
      }
      return LocalSearchResult(
        ok: true,
        answer: answer,
        error: '',
        sources: sources,
        model: servedModel,
      );
    } on TimeoutException {
      return _failure(
          'Your computer is not reachable. Check that it is on and on the '
          'same wifi, then try again.',
          <LocalSearchSource>[]);
    } catch (e) {
      _logger.error('LocalSearch', 'Ask failed', e);
      return _failure(
          'Your computer is not reachable. Check that it is on and on the '
          'same wifi, then try again.',
          <LocalSearchSource>[]);
    }
  }

  LocalSearchResult _failure(String error, List<LocalSearchSource> sources) {
    return LocalSearchResult(
      ok: false,
      answer: null,
      error: error,
      sources: sources,
      model: '',
    );
  }

  List<LocalSearchSource> _parseSources(dynamic raw) {
    if (raw is! List) return <LocalSearchSource>[];
    final sources = <LocalSearchSource>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final file = (item['file'] ?? '').toString();
      var title = (item['title'] ?? '').toString().trim();
      if (title.isEmpty) {
        var base = file.split('/').last;
        final dot = base.lastIndexOf('.');
        if (dot > 0) base = base.substring(0, dot);
        title = base.replaceAll('_', ' ');
      }
      sources.add(LocalSearchSource(
        file: file,
        folder: (item['folder'] ?? '').toString(),
        title: title,
        location: (item['location'] ?? '').toString(),
        score: double.tryParse('${item['score'] ?? 0}') ?? 0,
      ));
    }
    return sources;
  }
}
