import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
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

  static const _junkTags = {
    'script', 'style', 'noscript', 'template', 'iframe', 'svg', 'canvas',
    'form', 'button', 'input', 'select', 'textarea', 'object', 'embed',
    'nav', 'header', 'footer', 'aside',
  };

  static final _unlikelyRe = RegExp(
      r'combx|comment|sidebar|advert|ads?[-_]|promo|banner|breadcrumb|related|recommend|popup|modal|newsletter|subscribe|cookie|toolbar|widget|pagination|share|social|hidden|meta|menu|nav',
      caseSensitive: false);

  static final _positiveRe = RegExp(
      r'article|content|post|main|entry|body|text|story|blog|markdown|doc|page',
      caseSensitive: false);

  static const _seedSelectors = [
    'article',
    'main',
    '[role="main"]',
    '.post-content',
    '.article-content',
    '.entry-content',
    '.content-body',
    '.article-body',
    '.markdown-body',
    '.mw-parser-output',
    '#content',
    '.main-content',
  ];

  static const _fallbackSelectors = [
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

  static const _blockTags = {
    'address', 'article', 'aside', 'blockquote', 'br', 'dd', 'div', 'dl', 'dt',
    'fieldset', 'figcaption', 'figure', 'footer', 'form', 'h1', 'h2', 'h3',
    'h4', 'h5', 'h6', 'header', 'hr', 'li', 'main', 'nav', 'ol', 'p', 'pre',
    'section', 'table', 'tbody', 'td', 'th', 'thead', 'tr', 'ul',
  };

  String? _extractArticle(String body, String url) {
    final document = html_parser.parse(body);

    _stripJunk(document);

    dom.Element? best;
    try {
      best = _pickReadable(document);
    } catch (e) {
      _logger.error('PageFetcher', 'Readability scoring failed', e);
      best = null;
    }

    String content = '';
    if (best != null) {
      final buf = StringBuffer();
      _collectText(best, buf);
      content = buf.toString();
    }

    if (content.trim().length < 200) {
      content = _fallbackText(document);
    }

    content = content
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    if (content.length < 80) {
      _logger.log('PageFetcher', 'Content too short for $url: ${content.length} chars');
      return null;
    }

    if (content.length > 80000) {
      content = content.substring(0, 80000);
    }

    _logger.log('PageFetcher', 'Extracted ${content.length} chars from $url');
    return content;
  }

  /// Remove scripts, chrome, and unlikely containers before scoring.
  void _stripJunk(dom.Document document) {
    for (final tag in _junkTags) {
      for (final el in document.querySelectorAll(tag)) {
        el.remove();
      }
    }
    for (final el in document.querySelectorAll('[role]')) {
      final role = el.attributes['role']?.toLowerCase() ?? '';
      if (const {'navigation', 'banner', 'contentinfo', 'search', 'complementary', 'menu', 'menubar'}
          .contains(role)) {
        el.remove();
      }
    }
    for (final el in document.querySelectorAll('[aria-hidden="true"]')) {
      el.remove();
    }
    for (final el in List<dom.Element>.from(
        document.querySelectorAll('div, section, span, ul, ol'))) {
      final cls = '${el.classes.join(' ')} ${el.attributes['id'] ?? ''}';
      if (_unlikelyRe.hasMatch(cls) && !_positiveRe.hasMatch(cls)) {
        el.remove();
      }
    }
  }

  double _linkDensity(dom.Element el) {
    final textLength = el.text.trim().length;
    if (textLength == 0) return 0;
    var linkLength = 0;
    for (final a in el.querySelectorAll('a')) {
      linkLength += a.text.trim().length;
    }
    return linkLength / textLength;
  }

  /// Readability-style paragraph scoring: score real text blocks, propagate
  /// scores to ancestors, seed known article containers, pick the best.
  dom.Element? _pickReadable(dom.Document document) {
    final scores = <dom.Element, double>{};

    void bump(dom.Element? el, double pts) {
      if (el == null) return;
      final name = el.localName?.toLowerCase() ?? '';
      if (name == 'body' || name == 'html') return;
      scores[el] = (scores[el] ?? 0.0) + pts;
    }

    for (final el in document.querySelectorAll('p, pre, blockquote, h2, h3, td')) {
      final text = el.text.trim();
      if (text.length < 25) continue;
      final density = _linkDensity(el);
      if (density > 0.5) continue;
      final commas = ','.allMatches(text).length;
      final score = (1.0 + commas + text.length / 100.0) * (1.0 - density);

      scores[el] = (scores[el] ?? 0.0) + score;
      var pts = score;
      dom.Element? parent = el.parent;
      for (var level = 0; level < 3 && parent != null; level++) {
        bump(parent, pts);
        pts = pts / 2;
        parent = parent.parent;
      }
    }

    for (final selector in _seedSelectors) {
      for (final el in document.querySelectorAll(selector)) {
        bump(el, 12);
      }
    }

    dom.Element? best;
    var bestScore = 0.0;
    scores.forEach((el, s) {
      final textLen = el.text.trim().length;
      if (textLen < 200) return;
      final finalScore = s * (1.0 - _linkDensity(el));
      if (finalScore > bestScore) {
        bestScore = finalScore;
        best = el;
      }
    });

    return best;
  }

  void _collectText(dom.Node node, StringBuffer out) {
    if (node is dom.Text) {
      out.write(node.data);
      return;
    }
    if (node is dom.Element) {
      final tag = node.localName?.toLowerCase() ?? '';
      if (tag == 'br') {
        out.write('\n');
        return;
      }
      final isBlock = _blockTags.contains(tag);
      if (isBlock) out.write('\n');
      for (final child in node.nodes) {
        _collectText(child, out);
      }
      if (isBlock) out.write('\n');
    }
  }

  String _fallbackText(dom.Document document) {
    for (final selector in _fallbackSelectors) {
      final elements = document.querySelectorAll(selector);
      if (elements.isNotEmpty) {
        final content = elements.map((e) => e.text).join('\n\n');
        if (content.trim().length >= 100) return content;
      }
    }
    return document.body?.text ?? '';
  }
}
