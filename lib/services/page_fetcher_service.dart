import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:arya/services/debug_logger.dart';

class PageFetcherService {
  static final PageFetcherService instance = PageFetcherService._internal();
  PageFetcherService._internal();

  final _logger = DebugLogger();

  Future<String?> fetchPageContent(String url) async {
    try {
      final target = url.trim();
      if (target.isEmpty) {
        _logger.log('PageFetcher', 'Empty URL');
        return null;
      }

      _logger.log('PageFetcher', 'Fetching $target');
      final client = http.Client();
      try {
        final response = await client
            .get(
              Uri.parse(target),
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                'Accept-Language': 'en-US,en;q=0.5',
              },
            )
            .timeout(const Duration(seconds: 25));

        if (response.statusCode != 200) {
          _logger.log(
              'PageFetcher', 'Failed to fetch $target: HTTP ${response.statusCode}');
          // Retry once with mobile UA on failure
          if (response.statusCode == 403 || response.statusCode == 401) {
            return await _fetchWithMobileUa(target);
          }
          return null;
        }

        return _extractArticle(response.body, target);
      } finally {
        client.close();
      }
    } catch (e) {
      _logger.error('PageFetcher', 'Error fetching $url', e);
      return null;
    }
  }

  Future<String?> _fetchWithMobileUa(String url) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 13; SM-A536B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        },
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        _logger.log('PageFetcher', 'Mobile UA retry failed: HTTP ${response.statusCode}');
        return null;
      }
      return _extractArticle(response.body, url);
    } catch (e) {
      _logger.error('PageFetcher', 'Mobile UA retry error', e);
      return null;
    }
  }

  String? _extractArticle(String body, String url) {
    final document = html_parser.parse(body);

    for (final script in document.getElementsByTagName('script')) {
      script.remove();
    }
    for (final style in document.getElementsByTagName('style')) {
      style.remove();
    }
    for (final nav in document.querySelectorAll('nav, header, footer, aside, noscript')) {
      nav.remove();
    }

    String? content;
    const selectors = [
      'article',
      '[role="main"]',
      '.article-content',
      '.post-content',
      '.entry-content',
      '.content-body',
      '.article-body',
      '.markdown-body',
      '.mw-parser-output',
      'main',
      '#content',
      '.main-content',
      '#bodyContent',
    ];

    for (final selector in selectors) {
      final elements = document.querySelectorAll(selector);
      if (elements.isNotEmpty) {
        content = elements.map((e) => e.text).join('\n\n');
        if (content.trim().length >= 100) break;
      }
    }

    if (content == null || content.trim().isEmpty) {
      content = document.body?.text ?? '';
    }

    content = content
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    if (content.length < 80) {
      _logger.log('PageFetcher', 'Content too short for $url: ${content.length} chars');
      return null;
    }

    // Cap extremely long pages so TTS chunking stays manageable
    if (content.length > 80000) {
      content = content.substring(0, 80000);
    }

    _logger.log('PageFetcher', 'Extracted ${content.length} chars from $url');
    return content;
  }
}
