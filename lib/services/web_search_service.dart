import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html;

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
    try {
      final encodedQuery = Uri.encodeComponent(query);
      final response = await http.get(
        Uri.parse('https://html.duckduckgo.com/html/?q=$encodedQuery'),
        headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'},
      );
      if (response.statusCode != 200) return [];

      final document = html.parse(response.body);
      
      // Try multiple selectors for DuckDuckGo's changing HTML structure
      final resultElements = document.querySelectorAll('.result, .result__snippet, .web-result, .snippet, [class*="result"]');
      
      List<SearchResult> results = [];
      for (var element in resultElements) {
        if (results.length >= 10) break;
        
        // Try multiple title selectors
        var titleElement = element.querySelector('.result__a, .result__title, .result-title, a.result__url, h2 a, h3 a, .title a');
        var snippetElement = element.querySelector('.result__snippet, .result-snippet, .snippet, .description, [class*="snippet"]');
        
        // If snippet not found, try parent/sibling elements
        if (snippetElement == null) {
          snippetElement = element.querySelector('[class*="snippet"]') ?? element.parent?.querySelector('[class*="snippet"]');
        }
        
        // If title not found in element, try parent
        if (titleElement == null) {
          titleElement = element.querySelector('a[href^="http"]') ?? element.parent?.querySelector('a[href^="http"]');
        }
        
        // Extract title from text if element not found
        String title = titleElement?.text.trim() ?? '';
        String snippet = snippetElement?.text.trim() ?? '';
        String url = titleElement?.attributes['href'] ?? '';
        
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
        }
      }
      
      // Deduplicate by title
      final seen = <String>{};
      results = results.where((r) => seen.add(r.title.toLowerCase())).toList();
      
      return results.take(8).toList();
    } catch (e) {
      return [];
    }
  }
}
