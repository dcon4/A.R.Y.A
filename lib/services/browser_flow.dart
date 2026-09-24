import 'package:arya/services/debug_logger.dart';
import 'package:arya/services/page_fetcher_service.dart';
import 'package:arya/services/web_search_service.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:arya/services/web_search_service.dart' as ws;

class BrowserFlow {
  static const int PAGE_SIZE = 5;
  // ~1200 chars speaks for roughly 1-2 minutes at slow TTS rates; larger
  // chunks regularly exceeded the completion wait and aborted reading.
  static const int MAX_CHUNK_SIZE = 1200;

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
      r'^(?:please\s+)?(?:(?:new\s+)?search(?:\s+the\s+web)?(?:\s+for)?|google|look\s+up|find)\s+(.+)$',
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

  /// Normalize an utterance for command comparison: lowercase, strip
  /// punctuation, collapse whitespace. STT often adds trailing periods.
  String _norm(String text) {
    return text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Returns true if the utterance was consumed by the search flow.
  /// Returns false when the caller should treat it as a normal AI query.
  Future<bool> handleSpeechResult(String text, {Function()? onNextListen}) async {
    final lower = _norm(text);
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
      final explicit = extractSearchQuery(text);
      if (explicit == null && _isSearchTrigger(lower)) {
        // Bare activation phrase ("search", "google") with no query yet.
        await _speakAndListen("What would you like to search for? Say your query, or 'cancel' to exit.");
        return true;
      }
      await _performSearch(explicit ?? text.trim());
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

  /// Extract a result number from phrases like "three", "result three",
  /// "read result three", "the third one", "number 3", "3rd".
  /// Returns null when the phrase is not a number selection (so free-form
  /// questions go to AI instead of opening a result by accident).
  int? _extractNumber(String text) {
    final lower = _norm(text);
    if (lower.isEmpty) return null;

    // Command/filler words that may surround the number.
    const filler = {
      'the', 'a', 'an', 'read', 'reads', 'reading', 'please', 'open', 'opens',
      'opening', 'show', 'shows', 'select', 'choose', 'pick', 'result',
      'results', 'number', 'option', 'item', 'choice', 'of', 'page', 'go',
      'going', 'ahead', 'i', 'me', 'my', 'want', 'would', 'like', 'just',
      'really', 'um', 'uh', 'ah', 'yeah', 'yes', 'ok', 'okay',
    };
    const numberWords = {
      'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
      'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
      'first': 1, 'second': 2, 'third': 3, 'fourth': 4, 'fifth': 5,
      'sixth': 6, 'seventh': 7, 'eighth': 8, 'ninth': 9, 'tenth': 10,
    };
    // STT phonetic mishearings that should map to number words.
    const phonetic = {
      'won': 'one', 'wan': 'one', 'to': 'two', 'too': 'two', 'for': 'four',
      'ate': 'eight', 'fife': 'five', 'dive': 'five', 'hive': 'five',
      'tree': 'three', 'free': 'three', 'sir': 'three', 'siv': 'six',
      'seks': 'six', 'niner': 'nine',
    };

    final tokens = lower
        .split(' ')
        .where((t) => t.isNotEmpty && !filler.contains(t))
        .toList();
    if (tokens.isEmpty) return null;

    bool hasDigit(String t) => RegExp(r'\d').hasMatch(t);
    bool isNumberish(String t) =>
        hasDigit(t) || numberWords.containsKey(t) || phonetic.containsKey(t);

    // Every remaining token must be number-like, otherwise this is prose.
    if (!tokens.every(isNumberish)) return null;

    // Digits first ("result 3", "3rd").
    for (final t in tokens) {
      final d = RegExp(r'\d+').firstMatch(t);
      if (d != null) return int.parse(d.group(0)!);
    }
    // Exact number words as spoken ("third", "three").
    for (final t in tokens) {
      final v = numberWords[t];
      if (v != null) return v;
    }
    // Phonetic corrections ("tree" → three, "to" → two).
    for (final t in tokens) {
      final mapped = phonetic[t];
      if (mapped != null) return numberWords[mapped];
    }
    return null;
  }

  Future<bool> _handleResultSelection(String text) async {
    final lower = _norm(text);
    _logger.log('BrowserFlow', 'Result selection input: "$lower"');

    if (lower == 'cancel' || lower == 'exit' || lower == 'go back') {
      _handleCancel();
      return true;
    }
    if (lower == 'read all' ||
        lower == 'all' ||
        lower == 'read everything' ||
        lower.contains('read all') ||
        lower.contains('read them all')) {
      await _startReadingAll();
      return true;
    }
    if (lower == 'more results' || lower == 'more' || lower == 'next five') {
      await _showMoreResults();
      return true;
    }
    if (_isSearchTrigger(lower)) {
      // Use the shared extractor so vacuous phrases like "search the web"
      // prompt for a query instead of searching for "the web".
      final query = extractSearchQuery(text);
      if (query != null) {
        await _performSearch(query);
      } else {
        // Bare "new search" — clear old results so the next free-text
        // utterance is taken as the new query instead of going to AI.
        _allResults = [];
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

  Future<void> _openResult(int index, {bool announce = true}) async {
    if (index < 0 || index >= _allResults.length) {
      await _onError("Invalid result. Say a number or 'cancel'.");
      return;
    }

    final result = _allResults[index];
    _isReadingPage = false;
    _readingGen++;
    _logger.log('BrowserFlow', 'Opening result ${index + 1}: ${result.title} (${result.url})');

    if (announce) {
      await _onSpeak("Opening: ${result.title}.");
    }

    try {
      final url = result.url.trim();
      if (url.isEmpty) {
        _logger.log('BrowserFlow', 'Empty URL for result ${index + 1}: ${result.title}');
        if (_readingAllSequentially) {
          await _advanceToNextResult();
        } else {
          await _onError("That result has no readable link. Here is the snippet: ${result.snippet}. Say a number, 'new search', or 'cancel'.");
        }
        return;
      }

      final content = await PageFetcherService.instance.fetchPageContent(url);

      if (content == null || content.isEmpty) {
        _logger.log('BrowserFlow', 'Fetch failed for $url — using snippet');
        if (_readingAllSequentially) {
          await _advanceToNextResult();
        } else {
          await _onError("Could not fetch the full article. Here is the snippet: ${result.snippet}. Say a number, 'new search', or 'cancel'.");
        }
        return;
      }

      _currentPageChunks = _splitAtSentences(content, MAX_CHUNK_SIZE);
      _currentChunkIndex = 0;
      _readingGen++;
      _isReadingPage = true;
      final gen = _readingGen;
      _logger.log('BrowserFlow', 'Reading ${_currentPageChunks.length} chunk(s)');

      await _onSpeak("Reading ${result.title}.");
      await _readNextChunk(gen);
    } catch (e) {
      _logger.error('BrowserFlow', 'Error reading page', e);
      if (_readingAllSequentially) {
        await _advanceToNextResult();
      } else {
        _readingAllSequentially = false;
        await _onError("Error reading page: $e");
      }
    }
  }

  /// Called when the user barges in: kills the in-flight chunk chain so the
  /// old article doesn't keep speaking its next chunk in the background.
  void invalidateReading() {
    _readingGen++;
  }

  /// Read-all keeps going on its own: one short transition line, then the
  /// next article. No "say next or skip" prompt between articles.
  Future<void> _advanceToNextResult() async {
    final nextIndex = _currentResultIndex + 1;
    if (_allResults.isNotEmpty && nextIndex < _allResults.length) {
      _currentResultIndex = nextIndex;
      await _onSpeak("Finished with that article. Continuing to the next article.");
      if (_allResults.isEmpty) return; // cancelled during the transition
      await _openResult(nextIndex, announce: false);
    } else {
      _isReadingPage = false;
      _readingAllSequentially = false;
      await _speakAndListen("You have reached the end of the search results.");
    }
  }

  Future<void> _readNextChunk(int gen) async {
    if (!_isReadingPage || gen != _readingGen) return;
    if (_currentChunkIndex >= _currentPageChunks.length) {
      await _handleChunkEnd();
      return;
    }

    final chunk = _currentPageChunks[_currentChunkIndex];
    await _onSpeak("Part ${_currentChunkIndex + 1} of ${_currentPageChunks.length}. ${chunk}");
    _currentChunkIndex++;
    await _readNextChunk(gen);
  }

  Future<void> _handleChunkEnd() async {
    if (!_readingAllSequentially) {
      await _speakAndListen("End of article. Say a number, 'new search', or 'cancel'.");
      return;
    }

    await _advanceToNextResult();
  }

  Future<void> _handleReadingCommands(String text) async {
    final lower = _norm(text);
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
      await _readNextChunk(_readingGen);
      return;
    }

    // Number selection while reading
    final number = _extractNumber(text);
    if (number != null && number >= 1 && number <= _allResults.length) {
      _currentResultIndex = number - 1;
      await _openResult(number - 1);
      return;
    }

    // Unrecognized — re-prompt, then keep reading where we left off so a
    // stray utterance doesn't end "read all" halfway through.
    await _speakAndListen("Say a number, 'next', 'new search', or 'cancel'.");
    if (_isReadingPage) {
      await _readNextChunk(_readingGen);
    }
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
