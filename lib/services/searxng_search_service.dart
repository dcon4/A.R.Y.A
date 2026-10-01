import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'debug_logger.dart';

class SearxngResult {
  final String title;
  final String url;
  final String snippet;

  SearxngResult({
    required this.title,
    required this.url,
    required this.snippet,
  });
}

/// Optional search source backed by the user's own SearXNG server.
/// SearXNG is a free, self-hosted metasearch program; it needs no API
/// key. It is used in two places: as prompt-injection grounding (like
/// Brave) and as an alternative source for the voice web search.
class SearxngSearchService {
  static final SearxngSearchService instance = SearxngSearchService._internal();
  SearxngSearchService._internal();

  static const _prefsUrl = 'searxng_base_url';
  static const _prefsEnabled = 'searxng_enabled';
  static const _prefsResearchOnly = 'searxng_research_only';
  static const _prefsWebBackend = 'web_search_backend';

  final _logger = DebugLogger();

  static Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_prefsUrl) ?? '').trim();
  }

  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsUrl, url.trim());
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsEnabled) ?? false;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsEnabled, enabled);
  }

  static Future<bool> isResearchOnly() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsResearchOnly) ?? false;
  }

  static Future<void> setResearchOnly(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsResearchOnly, value);
  }

  /// Which source the voice web search uses: DuckDuckGo (default)
  /// or the user's own SearXNG server.
  static Future<bool> isVoiceSearchBackend() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_prefsWebBackend) ?? 'duckduckgo') == 'searxng';
  }

  static Future<void> setVoiceSearchBackend({required bool useSearxng}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsWebBackend, useSearxng ? 'searxng' : 'duckduckgo');
  }

  /// Query the SearXNG JSON API. Returns [] when no address is set,
  /// the server is unreachable, or JSON is not enabled - callers fall
  /// back to their other source.
  Future<List<SearxngResult>> search(String query, {int count = 10}) async {
    var base = await getBaseUrl();
    if (base.isEmpty) {
      _logger.log('SearXNG', 'No address set');
      return [];
    }
    if (!base.startsWith('http://') && !base.startsWith('https://')) {
      base = 'http://$base';
    }
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }

    try {
      final uri = Uri.parse('$base/search').replace(queryParameters: {
        'q': query,
        'format': 'json',
        'language': 'en',
      });
      final response = await http
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'User-Agent': 'ARYA/1.0 (voice assistant)',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        _logger.error(
            'SearXNG', 'HTTP ${response.statusCode} from $base - is JSON enabled in SearXNG?');
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final raw = data['results'] as List<dynamic>? ?? [];
      final results = <SearxngResult>[];
      for (final item in raw) {
        if (results.length >= count) break;
        final m = item as Map<String, dynamic>;
        final title = (m['title'] ?? '').toString().trim();
        final url = (m['url'] ?? '').toString().trim();
        final snippet = (m['content'] ?? '').toString().trim();
        if (title.isEmpty || url.isEmpty) continue;
        results.add(SearxngResult(title: title, url: url, snippet: snippet));
      }
      _logger.log('SearXNG', '"${query.length > 60 ? query.substring(0, 60) : query}" returned ${results.length} results');
      return results;
    } catch (e) {
      _logger.error('SearXNG', 'Request failed', e);
      return [];
    }
  }
}
