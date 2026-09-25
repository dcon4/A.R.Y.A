import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'debug_logger.dart';

class BraveSearchResult {
  final String title;
  final String url;
  final String snippet;

  BraveSearchResult({
    required this.title,
    required this.url,
    required this.snippet,
  });
}

class BraveSearchService {
  static const _prefsKey = 'brave_search_api_key';
  static const _prefsEnabled = 'brave_search_enabled';

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

  static const _prefsResearchOnly = 'brave_research_only';

  /// When true, Brave is only queried for research-type questions.
  static Future<bool> isResearchOnly() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsResearchOnly) ?? false;
  }

  static Future<void> setResearchOnly(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsResearchOnly, value);
  }

  Future<List<BraveSearchResult>> search(String query) async {
    final apiKey = await BraveSearchService.getApiKey();
    if (apiKey.isEmpty) {
      _logger.log('BraveSearch', 'No API key set');
      return [];
    }

    try {
      // Brave rejects queries longer than 200 bytes with HTTP 422.
      var q = query.trim();
      if (q.length > 180) {
        final cut = q.lastIndexOf(' ', 180);
        q = q.substring(0, cut > 60 ? cut : 180);
      }
      if (q != query) {
        _logger.log('BraveSearch', 'Query shortened to: "$q"');
      }

      final uri = Uri.parse('https://api.search.brave.com/res/v1/web/search')
          .replace(queryParameters: {
        'q': q,
        'count': '5',
        'extra_snippets': 'true',
        'search_lang': 'en',
      });

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'Accept-Encoding': 'gzip',
          'X-Subscription-Token': apiKey,
        },
      );

      if (response.statusCode != 200) {
        final body = response.body;
        _logger.error('BraveSearch',
            'API error HTTP ${response.statusCode}: ${body.length > 500 ? body.substring(0, 500) : body}');
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['web']?['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) {
        _logger.log('BraveSearch', 'No results for query');
        return [];
      }

      return results.take(5).map((r) {
        final snippets = r['extra_snippets'] as List<dynamic>?;
        final snippet = r['description'] as String? ?? '';
        if (snippets != null && snippets.isNotEmpty) {
          return BraveSearchResult(
            title: r['title'] as String? ?? '',
            url: r['url'] as String? ?? '',
            snippet: snippets.join(' '),
          );
        }
        return BraveSearchResult(
          title: r['title'] as String? ?? '',
          url: r['url'] as String? ?? '',
          snippet: snippet,
        );
      }).toList();
    } catch (e) {
      _logger.error('BraveSearch', 'Request failed', e);
      return [];
    }
  }

  String formatResults(List<BraveSearchResult> results) {
    if (results.isEmpty) return '';
    final buffer = StringBuffer();
    buffer.writeln('Here are search results that you should use to answer the user\'s question. '
        'Cite sources by referring to the numbered items below. '
        'If the search results do not contain the answer, say so honestly.');
    buffer.writeln('');
    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      buffer.writeln('${i + 1}. ${r.title}');
      buffer.writeln('   URL: ${r.url}');
      buffer.writeln('   ${r.snippet}');
      buffer.writeln('');
    }
    return buffer.toString();
  }
}
