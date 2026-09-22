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
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.5',
        },
      );
      logger.log('WebSearchService', 'Response status: ${response.statusCode}, body length: ${response.body.length}');
      
      if (response.statusCode != 200) {
        logger.log('WebSearchService', 'Non-200 status: ${response.statusCode}');
        return [];
      }

      final document = html.parse(response.body);
      
      // DuckDuckGo HTML structure (as of 2024): results are in .result class
      // Each result has: .result__title (link with title), .result__snippet (text)
      final resultElements = document.querySelectorAll('.result');
      logger.log('WebSearchService', 'Found ${resultElements.length} result elements');
      
      List<SearchResult> results = [];
      for (var element in resultElements) {
        if (results.length >= 8) break;
        
        // Title is in .result__title > a or .result__url
        var titleElement = element.querySelector('.result__title a, .result__title, .result__url a');
        // Snippet is in .result__snippet
        var snippetElement = element.querySelector('.result__snippet, .result__snippet__text');
        
        // Fallback: try broader selectors
        titleElement ??= element.querySelector('a.result__url, h2 a, h3 a, .title a');
        snippetElement ??= element.querySelector('.snippet, [class*="snippet"], .description');
        
        String title = titleElement?.text.trim() ?? '';
        String snippet = snippetElement?.text.trim() ?? '';
        String url = titleElement?.attributes['href'] ?? '';
        
        // Clean up URL if it's a redirect
        if (url.contains('uddg=')) {
          final uri = Uri.parse(url);
          final uddg = uri.queryParameters['uddg'];
          if (uddg != null) url = uddg;
        }
        
        // Fallback: extract from element text
        if (title.isEmpty && element.text.trim().isNotEmpty) {
          final lines = element.text.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
          if (lines.isNotEmpty) {
            title = lines.first.trim();
            if (lines.length > 1) snippet = lines[1].trim();
          }
        }
        
        if (title.isNotEmpty && snippet.isNotEmpty) {
          results.add(SearchResult(title: title, snippet: snippet, url: url));
          logger.log('WebSearchService', 'Added result: $title');
        }
      }
      
      // Deduplicate by title
      final seen = <String>{};
      results = results.where((r) => seen.add(r.title.toLowerCase())).toList();
      
      logger.log('WebSearchService', 'Returning ${results.length} results');
      return results.take(8).toList();
    } catch (e, st) {
      logger.error('WebSearchService', 'Search error', e);
      logger.error('WebSearchService', 'Stack trace: $st');
      return [];
    }
  }
}
