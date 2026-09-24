import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html;
import 'package:arya/services/debug_logger.dart';

class SearchResult {
  final String title;
  final String snippet;
  final String url;

  SearchResult({required this.title, required this.snippet, required this.url});
}

class WebSearchService {
  static final WebSearchService instance = WebSearchService._internal();
  WebSearchService._internal();

  Future<List<SearchResult>> search(String query) async {
    final logger = DebugLogger();
    try {
      final encodedQuery = Uri.encodeComponent(query);
      final url = 'https://html.duckduckgo.com/html/?q=$encodedQuery';
      logger.log('WebSearchService', 'Searching: $query');
      logger.log('WebSearchService', 'URL: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.5',
        },
      ).timeout(const Duration(seconds: 20));
      logger.log(
          'WebSearchService', 'Response status: ${response.statusCode}, body length: ${response.body.length}');

      if (response.statusCode != 200) {
        logger.log('WebSearchService', 'Non-200 status: ${response.statusCode}');
        return [];
      }

      final document = html.parse(response.body);
      final resultElements = document.querySelectorAll('.result');
      logger.log('WebSearchService', 'Found ${resultElements.length} result elements');

      List<SearchResult> results = [];
      for (var element in resultElements) {
        if (results.length >= 8) break;

        // Skip ads / tracking blocks when marked
        final classes = element.classes.join(' ').toLowerCase();
        if (classes.contains('ad') && !classes.contains('result')) continue;

        var titleElement = element.querySelector(
            '.result__title a[href], a.result__a[href], .result__title, h2 a[href], h3 a[href]');
        var snippetElement = element.querySelector(
            '.result__snippet, .result__snippet__text, .snippet, [class*="snippet"], .description');

        String title = titleElement?.text.trim() ?? '';
        String snippet = snippetElement?.text.trim() ?? '';
        String url = _extractUrl(element, titleElement);

        // Fallback: extract from element text
        if (title.isEmpty && element.text.trim().isNotEmpty) {
          final lines = element
              .text
              .trim()
              .split('\n')
              .where((l) => l.trim().isNotEmpty)
              .toList();
          if (lines.isNotEmpty) {
            title = lines.first.trim();
            if (lines.length > 1 && snippet.isEmpty) snippet = lines[1].trim();
          }
        }

        if (title.isEmpty) continue;
        if (snippet.isEmpty) {
          // Still keep the result if we have a URL — better than dropping it.
          snippet = title;
        }

        if (url.isEmpty) {
          logger.log('WebSearchService', 'Skipping result with empty URL: $title');
          continue;
        }

        results.add(SearchResult(title: title, snippet: snippet, url: url));
        logger.log('WebSearchService', 'Added result: $title -> $url');
      }

      // Deduplicate by URL (more reliable than title)
      final seen = <String>{};
      results = results.where((r) => seen.add(r.url.toLowerCase())).toList();

      logger.log('WebSearchService', 'Returning ${results.length} results');
      return results.take(8).toList();
    } catch (e, st) {
      logger.error('WebSearchService', 'Search error', e);
      logger.error('WebSearchService', 'Stack trace: $st');
      return [];
    }
  }

  /// Pull a real http(s) article URL out of a DuckDuckGo result element.
  String _extractUrl(html.Element element, html.Element? titleElement) {
    final candidates = <String>[];

    if (titleElement != null) {
      final href = titleElement.attributes['href'];
      if (href != null && href.isNotEmpty) candidates.add(href);
    }

    // Prefer main result anchors, then any http link in the block.
    for (final a in element.querySelectorAll('a[href]')) {
      final href = a.attributes['href'] ?? '';
      if (href.isNotEmpty) candidates.add(href);
    }

    for (final raw in candidates) {
      final resolved = _resolveDdgoUrl(raw);
      if (resolved != null) return resolved;
    }
    return '';
  }

  String? _resolveDdgoUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return null;

    // Protocol-relative
    if (url.startsWith('//')) url = 'https:$url';

    // DuckDuckGo redirect: /l/?uddg=<encoded>
    if (url.contains('uddg=')) {
      try {
        final uri = url.startsWith('http')
            ? Uri.parse(url)
            : Uri.parse('https://duckduckgo.com$url');
        final uddg = uri.queryParameters['uddg'];
        if (uddg != null && uddg.isNotEmpty) {
          url = Uri.decodeFull(uddg);
        }
      } catch (_) {
        // Fall through to manual decode
        final match = RegExp(r'uddg=([^&]+)').firstMatch(url);
        if (match != null) {
          try {
            url = Uri.decodeComponent(match.group(1)!);
          } catch (_) {}
        }
      }
    }

    // Relative DDG paths without a target are useless
    if (url.startsWith('/') && !url.startsWith('//')) return null;
    if (url.startsWith('javascript:') || url.startsWith('mailto:')) return null;

    if (!url.startsWith('http://') && !url.startsWith('https://')) return null;

    // Reject DDG self-links
    try {
      final host = Uri.parse(url).host.toLowerCase();
      if (host.contains('duckduckgo.com')) return null;
    } catch (_) {
      return null;
    }

    return url;
  }
}
