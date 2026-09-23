import 'dart:async';
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
  late Function(String) _onSpeak;
  late Function() _onListeningStarted;
  late Function() _onIdle;
  late Function(String) _onError;

  Future<void> start({
    required Function(String) onSpeak,
    required Function() onListeningStarted,
    required Function() onIdle,
    required Function(String) onError,
  }) async {
    _onSpeak = onSpeak;
    _onListeningStarted = onListeningStarted;
    _onIdle = onIdle;
    _onError = onError;
    _resetState();
    await _askForSearch();
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

  Future<void> _askForSearch() async {
    _onSpeak?.call("What would you like to search for? Say your query, or 'cancel' to exit.");
    // Caller should start listening after TTS completes
  }

  Future<void> handleSpeechResult(String text, {required Function(String) onNextListen}) async {
    final lower = text.trim().toLowerCase();

    if (lower == 'cancel' || lower == 'exit' || lower == 'go back') {
      _handleCancel();
      return;
    }

    if (_isReadingPage) {
      await _handleReadingCommands(text);
      return;
    }

    if (_allResults.isEmpty) {
      // In search input phase
      if (text.trim().isEmpty) {
        _onError?.call("I didn't hear a search query. Try again.");
        return;
      }
      await _performSearch(text.trim());
      return;
    }

    // In results selection phase
    await _handleResultSelection(text);
  }

  Future<void> _performSearch(String query) async {
    _onSpeak?.call("Searching for: $query.");

    try {
      final results = await WebSearchService.instance.search(query);
      if (results.isEmpty) {
        _onError?.call("No results found for '$query'. Say another query or 'cancel'.");
        return;
      }

      _allResults = results;
      _pageOffset = 0;
      _currentResultIndex = 0;
      _readingAllSequentially = false;

      await _presentCurrentPage();
    } catch (e) {
      _onError?.call("Search failed: $e");
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

    _onSpeak?.call(summary);
    // Caller should start listening after TTS
  }

  List<ws.SearchResult> _currentPageResults() {
    final start = _pageOffset;
    final end = (_pageOffset + 5).clamp(0, _allResults.length);
    return _allResults.sublist(start, end);
  }

  Future<void> _handleResultSelection(String text) async {
    final lower = text.trim().toLowerCase();

    if (lower == 'cancel' || lower == 'exit' || lower == 'go back') {
      _handleCancel();
      return;
    }
    if (lower == 'read all' || lower == 'all' || lower.contains('read all')) {
      await _startReadingAll();
      return;
    }
    if (lower == 'more results' || lower == 'more' || lower == 'next five') {
      await _showMoreResults();
      return;
    }
    if (lower == 'new search') {
      _pageOffset = 0;
      _currentResultIndex = 0;
      _readingAllSequentially = false;
      await _askForSearch();
      return;
    }
    if (lower == 'repeat' || lower == 'refresh') {
      _onSpeak?.call("Repeating results.");
      await _presentCurrentPage();
      return;
    }

    // Check for number
    final number = _extractNumber(text);
    if (number != null && number >= 1 && number <= _allResults.length) {
      _currentResultIndex = number - 1;
      _readingAllSequentially = false;
      await _openResult(_currentResultIndex);
      return;
    }

    if (text.trim().isNotEmpty) {
      // Treat as new search query
      await _performSearch(text.trim());
      return;
    }

    _onError?.call("Say a result number, 'read all', 'more results', 'new search', or 'cancel'.");
    // Caller should restart listening
  }

  Future<void> _showMoreResults() async {
    final nextPageStart = _pageOffset + 5;
    if (nextPageStart < _allResults.length) {
      _pageOffset = nextPageStart;
      _currentResultIndex = _pageOffset;
      await _presentCurrentPage();
    } else {
      _onSpeak?.call("No more results available. Say a number, 'new search', or 'cancel'.");
    }
  }

  Future<void> _startReadingAll() async {
    _readingAllSequentially = true;
    _currentResultIndex = _pageOffset;
    await _openResult(_currentResultIndex);
  }

  Future<void> _openResult(int index) async {
    if (index < 0 || index >= _allResults.length) {
      _onError?.call("Invalid result. Say a number or 'cancel'.");
      return;
    }

    final result = _allResults[index];
    _onSpeak?.call("Opening: ${result.title}.");
    _isReadingPage = true;
    _readingGen++;

    try {
      final content = await PageFetcherService.instance.fetchPageContent(_allResults[index].url);

      if (content == null || content.isEmpty) {
        _onError?.call("Could not fetch the full article. Here is the snippet: ${_allResults[index].snippet}. Say 'next', a number, 'new search', or 'cancel'.");
        return;
      }

      _currentPageChunks = _splitAtSentences(content, 3500);
      _currentChunkIndex = 0;
      _readingGen++;
      _isReadingPage = true;

      _onSpeak?.call("Reading ${_allResults[_currentResultIndex].title}.");
      await _readNextChunk();
    } catch (e) {
      _onError?.call("Error reading page: $e");
    }
  }

  Future<void> _readNextChunk() async {
    if (!_isReadingPage) return;
    if (_currentChunkIndex >= _currentPageChunks.length) {
      await _handleChunkEnd();
      return;
    }

    final chunk = _currentPageChunks[_currentChunkIndex];
    await _speakAndWait("Part ${_currentChunkIndex + 1} of ${_currentPageChunks.length}. ${chunk}");
    _currentChunkIndex++;
    await _readNextChunk();
  }

  Future<void> _handleChunkEnd() async {
    if (!_readingAllSequentially) {
      _onSpeak?.call("End of article. Say 'next', 'skip', 'new search', or 'cancel'.");
      return;
    }

    final nextIndex = _currentResultIndex + 1;
    if (nextIndex < _allResults.length) {
      _onSpeak?.call("End of article. Moving to the next result. Say 'skip' to skip, or 'cancel'.");
      // Wait for command - handled externally
    } else {
      _onSpeak?.call("You have reached the end of the search results.");
      _isReadingPage = false;
      _readingAllSequentially = false;
    }
  }

  Future<void> _handleReadingCommands(String text) async {
    final lower = text.trim().toLowerCase();

    if (lower == 'cancel' || lower == 'exit' || lower == 'go back') {
      _isReadingPage = false;
      _readingAllSequentially = false;
      _allResults = [];
      _onIdle?.call();
      return;
    }

    if (lower == 'skip' && _readingAllSequentially) {
      _currentResultIndex++;
      if (_currentResultIndex < _allResults.length) {
        await _openResult(_currentResultIndex);
      } else {
        _onSpeak?.call("No more results to skip to.");
        _isReadingPage = false;
        _readingAllSequentially = false;
      }
      return;
    }

    if (lower == 'new search') {
      _isReadingPage = false;
      _readingAllSequentially = false;
      _allResults = [];
      await _askForSearch();
      return;
    }

    if (lower == 'skip' && !_readingAllSequentially) {
      _onSpeak?.call("Say 'next' or 'cancel'.");
      return;
    }

    if (lower == 'next') {
      if (_readingAllSequentially) {
        _currentResultIndex++;
        if (_currentResultIndex < _allResults.length) {
          await _openResult(_currentResultIndex);
        } else {
          _onSpeak?.call("No more results.");
          _isReadingPage = false;
          _readingAllSequentially = false;
        }
      } else {
        _onSpeak?.call("Say 'read all' to read sequentially, or a number to open a result.");
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
    _onSpeak?.call("Say 'skip', 'next', 'new search', or 'cancel'.");
  }

  Future<void> _performSearch(String query) async {
    _onSpeak?.call("Searching for: $query.");

    try {
      final results = await WebSearchService.instance.search(query);
      if (results.isEmpty) {
        _onError?.call("No results found for '$query'. Say another query or 'cancel'.");
        return;
      }

      _allResults = results;
      _pageOffset = 0;
      _currentResultIndex = 0;
      _readingAllSequentially = false;

      await _presentCurrentPage();
    } catch (e) {
      _onError?.call("Search failed: $e");
    }
  }

  void _handleCancel() {
    _allResults = [];
    _pageOffset = 0;
    _currentResultIndex = 0;
    _readingAllSequentially = false;
    _isReadingPage = false;
    _onIdle?.call();
  }

  int? _extractNumber(String text) {
    final lower = text.trim().toLowerCase();

    // Phonetic corrections
    final corrected = lower
        .replaceAll(RegExp(r'\bwon\b'), 'one')
        .replaceAll(RegExp(r'\bto\b'), 'two')
        .replaceAll(RegExp(r'\btoo\b'), 'two')
        .replaceAll(RegExp(r'\bfor\b'), 'four')
        .replaceAll(RegExp(r'\bate\b'), 'eight')
        .replaceAll(RegExp(r'\bfife\b'), 'five')
        .replaceAll(RegExp(r'\bdive\b'), 'five')
        .replaceAll(RegExp(r'\bhive\b'), 'five');

    // Try digit
    final digitMatch = RegExp(r'^\d+$').hasMatch(corrected);
    if (digitMatch) return int.parse(corrected);

    // Try number words
    const numberWords = {
      'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
      'six': 6, 'seven': 7, 'eight': 8, 'nine': 8, 'ten': 10,
      'first': 1, 'second': 2, 'third': 3,
    };
    return numberWords[corrected];
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

  Future<void> _speakAndWait(String text) async {
    final completer = Completer<void>();
    await _tts.speak(text);
    await completer.future.timeout(const Duration(seconds: 60));
  }
}