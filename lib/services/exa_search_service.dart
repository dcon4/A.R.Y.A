import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'debug_logger.dart';

class ExaSearchResult {
  final String title;
  final String url;
  final String snippet;

  ExaSearchResult({
    required this.title,
    required this.url,
    required this.snippet,
  });
}

/// Exa web search (exa.ai). Two jobs:
///
/// 1. Grounding - feed fresh results into the model prompt, alongside
///    SearXNG and Brave in the same order-of-operations style.
/// 2. Article reading - pull clean page text straight from Exa when the
///    voice web search opens a page, so the fetch step is skipped.
class ExaSearchService {
  static const _prefsKey = 'exa_search_api_key';
  static const _prefsEnabled = 'exa_search_enabled';
  static const _prefsResearchOnly = 'exa_research_only';

  final _logger = DebugLogger();

  static Future<String> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKey) ?? '';
  }

  static Future<void> setApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, key);
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsEnabled) ?? false;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsEnabled, enabled);
  }

  /// When true, Exa is only queried for research-type questions.
  static Future<bool> isResearchOnly() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsResearchOnly) ?? false;
  }

  static Future<void> setResearchOnly(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsResearchOnly, value);
  }

  /// True when the user turned Exa on and a key is saved.
  static Future<bool> isUsable() async {
    final enabled = await isEnabled();
    final key = await getApiKey();
    return enabled && key.isNotEmpty;
  }

  /// Search the web through Exa. `type: fast` keeps latency low for
  /// voice use; `contents.text` returns a clean excerpt per result.
  Future<List<ExaSearchResult>> search(
    String query, {
    int numResults = 5,
    int snippetChars = 600,
  }) async {
    final apiKey = await getApiKey();
    if (apiKey.isEmpty) {
      _logger.log('ExaSearch', 'No API key set');
      return [];
    }

    try {
      final response = await http
          .post(
            Uri.parse('https://api.exa.ai/search'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'query': query,
              'numResults': numResults,
              'type': 'fast',
              'contents': {
                'text': {'maxCharacters': snippetChars},
              },
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        _logger.error('ExaSearch',
            'API error HTTP ${response.statusCode}: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}');
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) {
        _logger.log('ExaSearch', 'No results for query');
        return [];
      }

      final mapped = <ExaSearchResult>[];
      for (final r in results) {
        if (mapped.length >= numResults) break;
        final title = (r['title'] ?? '').toString().trim();
        final url = (r['url'] ?? '').toString().trim();
        var snippet = (r['text'] ?? '').toString().trim();
        if (title.isEmpty || url.isEmpty) continue;
        if (snippet.isEmpty) snippet = title;
        mapped.add(ExaSearchResult(title: title, url: url, snippet: snippet));
      }
      _logger.log('ExaSearch',
          '"${query.length > 60 ? query.substring(0, 60) : query}" returned ${mapped.length} results');
      return mapped;
    } catch (e) {
      _logger.error('ExaSearch', 'Request failed', e);
      return [];
    }
  }

  /// Fetch clean page text for one URL through Exa's contents endpoint.
  /// Returns null when Exa cannot read the page - callers fall back to
  /// the normal page fetcher.
  Future<String?> fetchPageText(String url) async {
    final apiKey = await getApiKey();
    if (apiKey.isEmpty) return null;

    try {
      final response = await http
          .post(
            Uri.parse('https://api.exa.ai/contents'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'ids': [url],
              'text': {'maxCharacters': 100000},
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode != 200) {
        _logger.error('ExaSearch',
            'Contents error HTTP ${response.statusCode} for $url');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final statuses = data['statuses'] as List<dynamic>?;
      if (statuses != null && statuses.isNotEmpty) {
        final status = (statuses.first as Map<String, dynamic>)['status'];
        if (status != null && status.toString() != 'success') {
          _logger.log('ExaSearch', 'Contents status for $url: $status');
          return null;
        }
      }
      final results = data['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;
      final text = (results.first as Map<String, dynamic>)['text']
              ?.toString() ??
          '';
      if (text.trim().isEmpty) return null;
      _logger.log('ExaSearch', 'Got ${text.length} chars of page text for $url');
      return text;
    } catch (e) {
      _logger.error('ExaSearch', 'Contents request failed for $url', e);
      return null;
    }
  }
}
