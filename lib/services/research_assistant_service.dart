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
  final String text;
  final double score;

  const LocalSearchSource({
    required this.file,
    required this.folder,
    required this.title,
    required this.location,
    required this.text,
    required this.score,
  });
}

class LocalSearchResult {
  final bool ok;
  final String? answer;
  final String error;
  final List<LocalSearchSource> sources;
  final String model;
  final String provider;
  final String scope;

  const LocalSearchResult({
    required this.ok,
    this.answer,
    required this.error,
    required this.sources,
    required this.model,
    required this.provider,
    this.scope = '',
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

  /// Which of the computer's providers the chosen model belongs to.
  /// Empty means the computer picks its own provider and model.
  static Future<String> getProvider() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString('local_search_provider') ?? '').trim();
  }

  static Future<void> setProvider(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('local_search_provider', value.trim());
  }

  Future<bool> checkReachable() async {
    final address = await getAddress();
    // 10s per try, one retry after 2 seconds: a single dropped first
    // packet must not read as "the computer is not reachable".
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        final response = await http
            .get(Uri.parse('$address/api/status'))
            .timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) return false;
        final data = jsonDecode(response.body);
        return data['ok'] == true;
      } catch (e) {
        _logger.log('LocalSearch',
            'Status check attempt $attempt failed (${e.runtimeType}): $e');
        if (attempt == 1) {
          await Future.delayed(const Duration(seconds: 2));
        }
      }
    }
    return false;
  }

  /// Ask the computer's Research Assistant.
  /// [scope] picks the search mode: 'public' searches the non-sensitive
  /// folders (the answer may come from a cloud model), 'private' searches
  /// only the private Keep folder and is always answered by the local
  /// model on the PC.
  Future<LocalSearchResult> ask(
    String question, {
    List<Map<String, String>> history = const [],
    String scope = 'public',
  }) async {
    final address = await getAddress();
    final model = await getModel();
    final provider = await getProvider();
    _logger.log(
        'LocalSearch', 'Ask "${question.length > 60 ? question.substring(0, 60) : question}" scope=$scope model=${model.isEmpty ? 'server default' : model} provider=${provider.isEmpty ? 'auto' : provider} history=${history.length}');

    try {
      final body = <String, dynamic>{'question': question, 'scope': scope};
      if (model.isNotEmpty) body['model'] = model;
      if (provider.isNotEmpty) body['provider'] = provider;
      if (history.isNotEmpty) body['history'] = history;

      final response = await _postAskWithRetry(Uri.parse('$address/api/ask'), body);

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
      final servedProvider = (data['provider'] ?? '').toString();
      final echoed = data['history'];
      final keptTurns = echoed is List ? echoed.length : 0;
      _logger.log('LocalSearch',
          'Answer ok=${data['ok'] == true} scope=${(data['scope'] ?? '').toString()} sources=${sources.length} model=$servedModel provider=$servedProvider history kept=$keptTurns of ${history.length}');

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
          provider: servedProvider,
          scope: (data['scope'] ?? '').toString(),
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
        provider: servedProvider,
        scope: (data['scope'] ?? '').toString(),
      );
    } on TimeoutException catch (e) {
      _logger.error('LocalSearch', 'Ask timed out after both attempts (${e.runtimeType})', e);
      return _failure(
          'Your computer is not reachable. Check that it is on and on the '
          'same wifi, then try again.',
          <LocalSearchSource>[]);
    } catch (e) {
      _logger.error('LocalSearch', 'Ask failed (${e.runtimeType})', e);
      return _failure(
          'Your computer is not reachable. Check that it is on and on the '
          'same wifi, then try again.',
          <LocalSearchSource>[]);
    }
  }

  /// POST the ask request. A connection-level failure (dropped packet,
  /// refused socket, timeout) is retried once after a 2 second pause
  /// before the "not reachable" message is produced. Every attempt is
  /// logged with the exact exception type so the debug log can tell
  /// connect-refused from timeout from anything else.
  Future<http.Response> _postAskWithRetry(
      Uri uri, Map<String, dynamic> body) async {
    Object? lastError;
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        return await http
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body),
            )
            // 300s: the local model needs ~10s to load after the PC boots,
            // and a cold disk adds more on top of the answer time.
            .timeout(const Duration(seconds: 300));
      } catch (e) {
        lastError = e;
        _logger.log('LocalSearch',
            'Ask attempt $attempt failed (${e.runtimeType}): $e');
        if (attempt < 2) {
          await Future.delayed(const Duration(seconds: 2));
        }
      }
    }
    throw lastError ?? Exception('ask failed');
  }

  LocalSearchResult _failure(String error, List<LocalSearchSource> sources) {
    return LocalSearchResult(
      ok: false,
      answer: null,
      error: error,
      sources: sources,
      model: '',
      provider: '',
    );
  }

  List<LocalSearchSource> _parseSources(dynamic raw) {
    if (raw is! List) return <LocalSearchSource>[];
    final sources = <LocalSearchSource>[];
    final seenTitles = <String>{};
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
      if (!seenTitles.add(title.toLowerCase())) continue;
      sources.add(LocalSearchSource(
        file: file,
        folder: (item['folder'] ?? '').toString(),
        title: title,
        location: (item['location'] ?? '').toString(),
        text: (item['text'] ?? '').toString().trim(),
        score: double.tryParse('${item['score'] ?? 0}') ?? 0,
      ));
    }
    return sources;
  }
}
