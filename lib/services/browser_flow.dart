import 'package:arya/services/debug_logger.dart';
import 'package:arya/services/page_fetcher_service.dart';
import 'package:arya/services/web_search_service.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:arya/services/web_search_service.dart' as ws;

class BrowserFlow {
  static const int PAGE_SIZE = 5;
  static const int MAX_CHUNK_SIZE = 3500;

  late FlutterTts _tts;
  late DebugLogger _logger;
  final WebSearchService _searchService = WebSearchService.instance;
  final PageFetcherService _pageFetcher = PageFetcherService.instance;

  // Allow injection from outside (e.g., from HomeScreen)
  set tts(FlutterTts value) => _tts = value;
  set logger(DebugLogger value) => _logger = value;

  // State
  List<ws.SearchResult> _allResults = [];
  int _pageOffset = 0;
  int _currentResultIndex = 0;
  List<String> _currentPageChunks = [];
  int _currentChunkIndex = 0;
  int _readingGen = 0;
  bool _readingAllSequentially = false;
  bool _isReadingPage = false;

  BrowserFlow._internal();

  static final BrowserFlow _instance = BrowserFlow._internal();
  factory BrowserFlow() => _instance;

  // Internal callback references
  late Future<void> Function(String) _onSpeak;
  late void Function() _onListeningStarted;
  late void Function() _onIdle;
  late Future<void> Function(String) _onError;

  bool get hasResults => _allResults.isNotEmpty;
  bool get isReading => _isReadingPage;

  Future<void> start({
    required Future<void> Function(String) onSpeak,
    required void Function() onListeningStarted,
    required void Function() onIdle,
    required Future<void> Function(String) onError,
    String? initialQuery,
  }) async {
    _onSpeak = onSpeak;
    _onListeningStarted = onListeningStarted;
    _onIdle = onIdle;
    _onError = onError;
    _resetState();
    final query = initialQuery?.trim();
    if (query != null && query.isNotEmpty) {
      await _performSearch(query);
    } else {
      await _speakAndListen("What would you like to search for? Say your query, or 'cancel' to exit.");
    }
  }

  /// Pull the query out of phrases like "search for cats" / "google cats".
  /// Returns null when the phrase only activates search mode.
  static String? extractSearchQuery(String text) {
    final lower = text.toLowerCase().trim();
    final m = RegExp(
      r'^(?:please\s+)?(?:search(?:\s+the\s+web)?(?:\s+for)?|google|look\s+up|find)\s+(.+)$',
    ).firstMatch(lower);
    if (m == null) return null;
    final q = m.group(1)!.trim();
    if (q.isEmpty || q == 'the web' || q == 'web' || q == 'internet' || q == 'online') {
      return null;
    }
    return q;
  }

  void _resetState() {
    _allResults = [];
    _pageOffset = 0;
    _currentResultIndex = 0;
    _currentPageChunks = [];
    _currentChunkIndex = 0;
    _readingGen = 0;
    _readingAllSequentially = false;
    _isReadingPage = false;
  }

  Future<void> _speakAndListen(String message) async {
    try {
      await _onSpeak(message);
    } catch (e) {
      _logger.error('BrowserFlow', 'Speak failed', e);
    } finally {
      _onListeningStarted();
    }
  }

  /// Returns true if the utterance was consumed by the search flow.
  /// Returns false when the caller should treat it as a normal AI query.
  Future<bool> handleSpeechResult(String text, {Function()? onNextListen}) async {
    final lower = text.trim().toLowerCase();
    _logger.log('BrowserFlow', 'handleSpeechResult: "$text" (reading=$_isReadingPage, results=${_allResults.length})');

    if (lower == 'cancel' || lower == 'exit' || lower == 'go back') {
      _handleCancel();
      return true;
    }

    if (_isReadingPage) {
      await _handleReadingCommands(text);
      return true;
    }

    if (_allResults.isEmpty) {
      // Search input phase — free text is the query the user was just asked for.
      if (text.trim().isEmpty) {
        await _onError("I didn't hear a search query. Try again.");
        return true;
      }
      await _performSearch(text.trim());
      return true;
    }

    // Results selection phase
    return _handleResultSelection(text);
  }

  Future<void> _performSearch(String query) async {
    _logger.log('BrowserFlow', 'Performing search: "$query"');
    await _onSpeak("Searching for: $query.");

    try {
      final results = await WebSearchService.instance.search(query);
      if (results.isEmpty) {
        await _onError("No results found for '$query'. Say another query or 'cancel'.");
        return;
      }

      _allResults = results;
      _pageOffset = 0;
      _currentResultIndex = 0;
      _readingAllSequentially = false;

      await _presentCurrentPage();
    } catch (e) {
      await _onError("Search failed: $e");
    }
  }

  Future<void> _presentCurrentPage() async {
    final pageResults = _currentPageResults();
    final totalResults = _allResults.length;
    final startNum = _pageOffset + 1;
    final endNum = _pageOffset + pageResults.length;

    String summary = "";
    if (_pageOffset == 0) {
      summary += "Found $totalResults result${totalResults == 1 ? "" : "s"}. ";
    } else {
      summary += "Results $startNum to $endNum of $totalResults. ";
    }

    for (int i = 0; i < pageResults.length; i++) {
      final r = pageResults[i];
      summary += "${_pageOffset + i + 1}: ${r.title}. ";
    }

    summary += "Say a number to open";
    if (pageResults.length > 1) summary += ", 'read all'";
    if (endNum < totalResults) summary += ", 'more results'";
    summary += ", 'new search', or 'cancel'.";

    _logger.log('BrowserFlow', 'Presenting results page ($startNum-$endNum of $totalResults)');
    await _speakAndListen(summary);
  }

  List<ws.SearchResult> _currentPageResults() {
    final start = _pageOffset;
    final end = (_pageOffset + 5).clamp(0, _allResults.length);
    return _allResults.sublist(start, end);
  }

  /// Explicit search keywords that mean "start a new search", not AI.
  bool _isSearchTrigger(String lower) {
    if (lower == 'new search' || lower == 'web search' || lower == 'find' || lower == 'search') {
      return true;
    }
    if (lower.startsWith('new search') ||
        lower.startsWith('search for ') ||
        lower.startsWith('search ') ||
        lower.startsWith('google ') ||
        lower.startsWith('look up ') ||
        lower.startsWith('look up') ||
        lower.startsWith('find ')) {
      return true;
    }
    // Word-boundary match so "research" does not trigger web search.
    return RegExp(r'\b(search|searching|google|duckduckgo|duck\s+duck\s+go|look\s+up)\b')
        .hasMatch(lower);
  }

  /// Extract a result number from phrases like "three", "3", "number 3", "the third one".
  int? _extractNumber(String text) {
    var lower = text.trim().toLowerCase();
    lower = lower.replaceAll(RegExp(r'[^\w\s]'), ' ').trim();
    if (lower.isEmpty) return null;

    // Common prefixes
    lower = lower
        .replaceFirst(RegExp(r'^(the|a|an|option|result|number|item|choice|pick|open)\s+'), '')
        .trim();

    // Phonetic and word corrections
    final corrected = lower
        .replaceAll(RegExp(r'\bwon\b'), 'one')
        .replaceAll(RegExp(r'\bto\b'), 'two')
        .replaceAll(RegExp(r'\btoo\b'), 'two')
        .replaceAll(RegExp(r'\bfor\b'), 'four')
        .replaceAll(RegExp(r'\bate\b'), 'eight')
        .replaceAll(RegExp(r'\bfife\b'), 'five')
        .replaceAll(RegExp(r'\bdive\b'), 'five')
        .replaceAll(RegExp(r'\bhive\b'), 'five')
        .replaceAll(RegExp(r'\btree\b'), 'three')
        .replaceAll(RegExp(r'\bfree\b'), 'three')
        .replaceAll(RegExp(r'\bsir\b'), 'three')
        .replaceAll(RegExp(r'\bone\b'), 'one')
        .trim();

    // Try digit (possibly with trailing words like "3 please")
    final digitMatch = RegExp(r'(\d+)').firstMatch(corrected);
    if (digitMatch != null) {
      return int.parse(digitMatch.group(1)!);
    }

    // Try number words anywhere in the phrase
    const numberWords = {
      'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
      'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
      'first': 1, 'second': 2, 'third': 3, 'fourth': 4, 'fifth': 5,
    };
    for (final entry in numberWords.entries) {
      if (corrected == entry.key || corrected.endsWith(' ${entry.key}')) {
        return entry.value;
      }
    }
    return numberWords[corrected];
  }

  Future<bool> _handleResultSelection(String text) async {
    final lower = text.trim().toLowerCase();
    _logger.log('BrowserFlow', 'Result selection input: "$lower"');

    if (lower == 'cancel' || lower == 'exit' || lower == 'go back') {
      _handleCancel();
      return true;
    }
    if (lower == 'read all' || lower == 'all' || lower.contains('read all')) {
      await _startReadingAll();
      return true;
    }
    if (lower == 'more results' || lower == 'more' || lower == 'next five') {
      await _showMoreResults();
      return true;
    }
    if (_isSearchTrigger(lower)) {
      // Explicit search keywords start a new search prompt (or take the query if present).
      final queryMatch = RegExp(
        r'^(?:new\s+search(?:\s+for)?|search(?:\s+for)?|google|look\s+up|find)\s+(.+)$',
      ).firstMatch(lower);
      if (queryMatch != null && queryMatch.group(1)!.trim().isNotEmpty) {
        await _performSearch(queryMatch.group(1)!.trim());
      } else {
        _pageOffset = 0;
        _currentResultIndex = 0;
        _readingAllSequentially = false;
        await _speakAndListen("What would you like to search for? Say your query, or 'cancel' to exit.");
      }
      return true;
    }
    if (lower == 'repeat' || lower == 'refresh') {
      await _onSpeak("Repeating results.");
      await _presentCurrentPage();
      return true;
    }

    // Check for number
    final number = _extractNumber(text);
    if (number != null) {
      _logger.log('BrowserFlow', 'Parsed number $number from "$text"');
      if (number >= 1 && number <= _allResults.length) {
        _currentResultIndex = number - 1;
        _readingAllSequentially = false;
        await _openResult(_currentResultIndex);
        return true;
      }
      await _onError("There are only ${_allResults.length} results. Say a number from 1 to ${_allResults.length}, or 'cancel'.");
      return true;
    }

    // Free text without search keywords in the results list is an AI question.
    // Only the initial "what would you like to search for?" prompt accepts free text as a query.
    _logger.log('BrowserFlow', 'No search keyword or number — handing off to AI: "$text"');
    return false;
  }

  Future<void> _showMoreResults() async {
    final nextPageStart = _pageOffset + 5;
    if (nextPageStart < _allResults.length) {
      _pageOffset = nextPageStart;
      _currentResultIndex = _pageOffset;
      await _presentCurrentPage();
    } else {
      await _speakAndListen("No more results available. Say a number, 'new search', or 'cancel'.");
    }
  }

  Future<void> _startReadingAll() async {
    _readingAllSequentially = true;
    _currentResultIndex = _pageOffset;
    await _openResult(_currentResultIndex);
  }

  Future<void> _openResult(int index) async {
    if (index < 0 || index >= _allResults.length) {
      await _onError("Invalid result. Say a number or 'cancel'.");
      return;
    }

    final result = _allResults[index];
    _isReadingPage = false;
    _readingGen++;
    _logger.log('BrowserFlow', 'Opening result ${index + 1}: ${result.title} (${result.url})');

    await _onSpeak("Opening: ${result.title}.");

    try {
      final url = result.url.trim();
      if (url.isEmpty) {
        _isReadingPage = false;
        await _onError("Could not fetch the full article. Here is the snippet: ${result.snippet}. Say a number, 'new search', or 'cancel'.");
        return;
      }

      final content = await PageFetcherService.instance.fetchPageContent(url);

      if (content == null || content.isEmpty) {
        _isReadingPage = false;
        await _onError("Could not fetch the full article. Here is the snippet: ${result.snippet}. Say a number, 'new search', or 'cancel'.");
        return;
      }

      _currentPageChunks = _splitAtSentences(content, 3500);
      _currentChunkIndex = 0;
      _readingGen++;
      _isReadingPage = true;
      _logger.log('BrowserFlow', 'Reading ${_currentPageChunks.length} chunk(s)');

      await _onSpeak("Reading ${result.title}.");
      await _readNextChunk();
    } catch (e) {
      _isReadingPage = false;
      _logger.error('BrowserFlow', 'Error reading page', e);
      await _onError("Error reading page: $e");
    }
  }

  Future<void> _readNextChunk() async {
    if (!_isReadingPage) return;
    if (_currentChunkIndex >= _currentPageChunks.length) {
      await _handleChunkEnd();
      return;
    }

    final chunk = _currentPageChunks[_currentChunkIndex];
    await _onSpeak("Part ${_currentChunkIndex + 1} of ${_currentPageChunks.length}. ${chunk}");
    _currentChunkIndex++;
    await _readNextChunk();
  }

  Future<void> _handleChunkEnd() async {
    if (!_readingAllSequentially) {
      await _speakAndListen("End of article. Say a number, 'new search', or 'cancel'.");
      return;
    }

    final nextIndex = _currentResultIndex + 1;
    if (nextIndex < _allResults.length) {
      await _speakAndListen("End of article. Moving to the next result. Say 'skip' to skip, or 'cancel'.");
    } else {
      _isReadingPage = false;
      _readingAllSequentially = false;
      await _speakAndListen("You have reached the end of the search results.");
    }
  }

  Future<void> _handleReadingCommands(String text) async {
    final lower = text.trim().toLowerCase();
    _logger.log('BrowserFlow', 'Reading command: "$lower"');

    if (lower == 'cancel' || lower == 'exit' || lower == 'go back') {
      _isReadingPage = false;
      _readingAllSequentially = false;
      _allResults = [];
      _onIdle();
      return;
    }

    if (lower == 'skip' && _readingAllSequentially) {
      _currentResultIndex++;
      if (_currentResultIndex < _allResults.length) {
        await _openResult(_currentResultIndex);
      } else {
        _isReadingPage = false;
        _readingAllSequentially = false;
        await _speakAndListen("No more results to skip to.");
      }
      return;
    }

    if (lower == 'new search' || _isSearchTrigger(lower)) {
      _isReadingPage = false;
      _readingAllSequentially = false;
      _allResults = [];
      await _speakAndListen("What would you like to search for? Say your query, or 'cancel' to exit.");
      return;
    }

    if (lower == 'skip' && !_readingAllSequentially) {
      await _speakAndListen("Say 'next' or 'cancel'.");
      return;
    }

    if (lower == 'next') {
      if (_readingAllSequentially) {
        _currentResultIndex++;
        if (_currentResultIndex < _allResults.length) {
          await _openResult(_currentResultIndex);
        } else {
          _isReadingPage = false;
          _readingAllSequentially = false;
          await _speakAndListen("No more results.");
        }
      } else {
        await _speakAndListen("Say a number to open a result, 'new search', or 'cancel'.");
      }
      return;
    }

    if (lower == 'repeat') {
      _currentChunkIndex = 0;
      await _readNextChunk();
      return;
    }

    // Number selection while reading
    final number = _extractNumber(text);
    if (number != null && number >= 1 && number <= _allResults.length) {
      _currentResultIndex = number - 1;
      await _openResult(number - 1);
      return;
    }

    // If unrecognized, re-prompt
    await _speakAndListen("Say a number, 'next', 'new search', or 'cancel'.");
  }

  void _handleCancel() {
    _logger.log('BrowserFlow', 'Cancel — leaving search mode');
    _allResults = [];
    _pageOffset = 0;
    _currentResultIndex = 0;
    _readingAllSequentially = false;
    _isReadingPage = false;
    _onIdle();
  }

  List<String> _splitAtSentences(String text, int maxChunk) {
    if (text.length <= maxChunk) return [text];
    final sentences = text.split(RegExp(r'(?<=[.!?])\s+'));
    final chunks = <String>[];
    var current = StringBuffer();
    for (final sentence in sentences) {
      if (current.length + sentence.length > maxChunk && current.isNotEmpty) {
        chunks.add(current.toString().trim());
        current = StringBuffer();
      }
      if (sentence.length > maxChunk) {
        for (var i = 0; i < sentence.length; i += maxChunk) {
          final end = (i + maxChunk < sentence.length) ? i + maxChunk : sentence.length;
          chunks.add(sentence.substring(i, end).trim());
        }
        continue;
      }
      current.write(sentence);
      current.write(' ');
    }
    if (current.isNotEmpty) {
      chunks.add(current.toString().trim());
    }
    return chunks;
  }
}
