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
      final response = await http.get(
        Uri.parse('https://html.duckduckgo.com/html/?q=$query'),
        headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'},
      );
      if (response.statusCode != 200) return [];

      final document = html.parse(response.body);
      final resultElements = document.querySelectorAll('.result');
      
      List<SearchResult> results = [];
      for (var element in resultElements.take(5)) {
        final titleElement = element.querySelector('.result__a');
        final snippetElement = element.querySelector('.result__snippet');
        
        if (titleElement != null && snippetElement != null) {
          results.add(SearchResult(
            title: titleElement.text.trim(),
            snippet: snippetElement.text.trim(),
            url: titleElement.attributes['href'] ?? '',
          ));
        }
      }
      return results;
    } catch (e) {
      return [];
    }
  }
}
