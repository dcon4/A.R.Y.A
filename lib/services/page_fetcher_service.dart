import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:arya/services/debug_logger.dart';

class PageFetcherService {
  static final PageFetcherService instance = PageFetcherService._internal();
  PageFetcherService._internal();

  final _logger = DebugLogger();

  Future<String?> fetchPageContent(String url) async {
    try {
      final client = http.Client();
      final response = await client.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 10; SM-A530F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36',
      }).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        _logger.log('PageFetcher', 'Failed to fetch $url: HTTP ${response.statusCode}');
        return null;
      }

      final document = html_parser.parse(response.body);

      // Remove script and style elements
      for (final script in document.getElementsByTagName('script')) {
        script.remove();
      }
      for (final style in document.getElementsByTagName('style')) {
        style.remove();
      }

      // Try common article selectors
      String? content;
      final selectors = [
        'article',
        '[role="main"]',
        '.article-content',
        '.post-content',
        '.entry-content',
        '.content-body',
        '.article-body',
        'main',
        '#content',
        '.main-content',
      ];

      for (final selector in selectors) {
        final elements = document.querySelectorAll(selector);
        if (elements.isNotEmpty) {
          content = elements.map((e) => e.text).join('\n\n');
          break;
        }
      }

      // Fallback to body text
      if (content == null || content.trim().isEmpty) {
        content = document.body?.text ?? '';
      }

      // Clean up whitespace
      content = content
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll(RegExp(r'\n\s*\n'), '\n\n')
          .trim();

      if (content.length < 100) {
        _logger.log('PageFetcher', 'Content too short for $url: ${content.length} chars');
        return null;
      }

      return content;
    } catch (e) {
      _logger.error('PageFetcher', 'Error fetching $url', e);
      return null;
    }
  }
}