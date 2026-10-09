import 'dart:async';
import 'dart:io';
import 'package:arya/models/memory_entry.dart';
import 'package:arya/screens/help_screen.dart';
import 'package:arya/screens/settings_screen.dart';
import 'package:share_plus/share_plus.dart';
import 'package:arya/services/api_providers.dart';
import 'package:arya/services/background_service.dart';
import 'package:arya/services/conversation_service.dart';
import 'package:arya/services/debug_logger.dart';
import 'package:arya/services/memory_service.dart';
import 'package:arya/services/openai_service.dart';
import 'package:arya/services/query_classifier.dart';
import 'package:arya/services/research_assistant_service.dart';
import 'package:arya/services/weather_service.dart';
import 'package:arya/services/web_search_service.dart';
import 'package:arya/services/wake_word_service.dart';
import 'package:arya/services/browser_flow.dart';
import 'package:arya/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

enum SearchState { idle, awaitingQuery, showingResults, readingResult }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final speechToText = SpeechToText();
  final FlutterTts flutterTts = FlutterTts();
  final OpenaiService openaiService = OpenaiService();
  final ConversationService conversationService = ConversationService();
  String lastWords = "";
  String? generatedContent;
  bool isLoading = false;
  bool _micReallyListening = false;
  final TextEditingController _textInputController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();
  final List<Map<String, String>> _messageHistory = [];
  bool _wakeWordPausedForSpeech = false;
  Timer? _speechTimeout;
  // Utterance stitching: the phone's speech service often declares the
  // result "final" after only ~1-2 s of silence, ignoring our pauseFor
  // setting. When that happens we keep collecting words in short re-listen
  // sessions and only dispatch after _pauseSec seconds of real silence.
  Timer? _stitchTimer;
  bool _stitchConfirming = false;
  String _stitchBase = '';
  String _stitchSession = '';
  int _stitchRelistens = 0;
  static const int _maxStitchRelistens = 30;
  void Function()? _stitchAction;
  bool _stitchFinishing = false;
  bool _confirmedThisTurn = false;
  DateTime _lastSpeechAt = DateTime.now();
  int _pauseSec = 12;
  int _listenSec = 60;
  Completer<void>? _announceCompleter;
  // Serializes speech so overlapping prompts can't orphan each other's
  // completion waiters (which caused 60-second TimeoutException stalls).
  Future<void> _speakChain = Future.value();
  // Bumped when the user barges in; queued speech from before is skipped.
  int _speakGen = 0;
  static const int _maxTtsChunkSize = 600;
  List<String> _responseChunks = [];
  int _responseChunkIndex = 0;
  // True only while a response is genuinely being read out, so a resume
  // never restarts a chunk chain that was already finished or abandoned.
  bool _responseSpeechActive = false;
  // Speech pause. Two independent causes hold speech: the user tapped the
  // notification's Pause Speech button, or a phone call is ringing or in
  // progress. While either cause is set, new speech is dropped and the TTS
  // engine is stopped; speech cut off mid-sentence is replayed on resume.
  bool _speechPausedByUser = false;
  bool _speechPausedByCall = false;
  // True while the TTS engine has actually been stopped for a pause.
  bool _ttsEnginePaused = false;
  // Text of the in-flight awaited utterance, so resume can restart it.
  String? _pendingSpokenText;
  // How often the wait loop re-checks the clock and the pause state.
  static const _ttsWaitSlice = Duration(milliseconds: 500);
  // Where the engine says it has read up to inside the current utterance.
  // Reset on every utterance start; stays 0 if the engine never reports
  // progress, which is logged at pause time so it can be spotted in a log.
  int _ttsProgressStart = 0;
  int _ttsProgressLength = 0;
  String _lastAiResponse = '';
  static const _btChannel = MethodChannel('arya.bluetooth_mic_toggle');
  QueryClassification? _pendingClassification;
  String _pendingQuery = '';
  bool _isConfirming = false;
  bool _localSearchPending = false;
  int _localSearchTurnsRemaining = 0;
  // Search scope of the current local-search session: 'public' (the
  // non-sensitive folders, cloud answer allowed) or 'private' (only the
  // private Keep folder, always answered by the local model on the PC).
  String _localSearchScope = 'public';
  Future<void> Function()? _retryAction;
  String _previousUserQuery = '';
  String _previousAiResponse = '';

  // Search State
    bool _readingAllSequentially = false;
    SearchState _searchState = SearchState.idle;
  List<SearchResult> _searchResults = [];
  int _selectedResultIndex = -1;

  // Browser Flow
  final BrowserFlow _browserFlow = BrowserFlow();
  bool _browserMode = false;
  String _webSearchResultsText = '';

  // Transient status line pinned to the top of the screen
  String? _statusMessage;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    initSpeechToText();
    initTextToSpeech();
    // BrowserFlow's injected dependencies must be set before any call to
    // reset(), including "New conversation" before a search ever ran.
    _browserFlow.tts = flutterTts;
    _browserFlow.logger = _logger;
    // Results go on screen as well as being spoken, and searches and
    // read articles are saved into the conversation transcript.
    _browserFlow.onResults = (results, query, elapsed) async {
      if (!mounted) return;
      if (results.isEmpty) {
        setState(() {
          _webSearchResultsText = '';
          generatedContent = 'No web search results for "$query".';
        });
        return;
      }
      final sb = StringBuffer('Search results for "$query":\n\n');
      for (var i = 0; i < results.length; i++) {
        sb.writeln('${i + 1}. ${results[i].title}');
        sb.writeln('   ${results[i].snippet}');
        sb.writeln('   ${results[i].url}');
        sb.writeln('');
      }
      final text = sb.toString().trimRight();
      setState(() {
        _webSearchResultsText = text;
        generatedContent = text;
      });
      conversationService.addEntry(ConversationEntry(
        userQuery: 'web search: $query',
        aiResponse: text,
        model: 'web search',
        provider: '',
        routingCategory: 'web_search',
        responseTime: elapsed,
      ));
      try {
        await conversationService.autoSave();
      } catch (e) {
        _logger.error('HomeScreen', 'Transcript save of search results failed', e);
      }
    };
    _browserFlow.onArticleRead = (title, url, text) async {
      if (!mounted) return;
      final article = text.length > 80000
          ? '${text.substring(0, 80000)}\n\n(article text truncated in transcript)'
          : text;
      setState(() {
        generatedContent = _webSearchResultsText.isEmpty
            ? 'Reading: $title\n$url\n\n$article'
            : '$_webSearchResultsText\n\nReading: $title\n$url\n\n$article';
      });
      conversationService.addEntry(ConversationEntry(
        userQuery: 'read article: $title',
        aiResponse: '$url\n\n$article',
        model: 'web search',
        provider: '',
        routingCategory: 'article_reading',
      ));
      try {
        await conversationService.autoSave();
      } catch (e) {
        _logger.error('HomeScreen', 'Transcript save of article failed', e);
      }
    };
    BackgroundService.setOnStartMicCallback(() {
      if (speechToText.isNotListening) {
        startListening();
      }
    });

    BackgroundService.setOnNewConversationCallback(() async {
      await _newConversation();
      systemSpeak("New conversation started");
    });

    BackgroundService.setOnToggleBraveSearchCallback(() async {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getBool('brave_search_enabled') ?? false;
      await prefs.setBool('brave_search_enabled', !current);
      systemSpeak(current ? "You have turned off Brave Search" : "Brave Search On");
    });

    BackgroundService.setOnToggleWebSearchCallback(() async {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getBool('web_search_enabled') ?? false;
      await prefs.setBool('web_search_enabled', !current);
      systemSpeak(current ? "You have turned search off" : "Searching the Web is on");
    });

    BackgroundService.setOnTriggerSecondOpinionCallback(() async {
      await _sendSecondOpinion();
    });

    BackgroundService.setOnRotateProviderCallback(() async {
      final prefs = await SharedPreferences.getInstance();
      final currentId = prefs.getString('api_provider') ?? 'openrouter';
      // 'local' is local-search only - its address exists on the PC, never
      // on the phone, so it must never become the general-chat provider.
      final selectable = apiProviders.where((p) => p.id != 'local').toList();
      final currentIndex = selectable.indexWhere((p) => p.id == currentId);
      final nextIndex = (currentIndex + 1) % selectable.length;
      final next = selectable[nextIndex];
      await prefs.setString('api_provider', next.id);
      if (next.defaultModel.isNotEmpty) {
        await prefs.setString('api_model', next.defaultModel);
      }
      systemSpeak(next.name);
    });

    BackgroundService.setOnRotateAnnounceModeCallback(() async {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getInt('mic_announcement_mode') ?? 0;
      final next = (current + 1) % 3;
      await prefs.setInt('mic_announcement_mode', next);
      final labels = ["Silent", "Listening", "Provider + Model"];
      systemSpeak("Announce ${labels[next]}");
    });

    BackgroundService.setOnToggleTtsPauseCallback(() async {
      await _toggleSpeechPauseByUser();
    });

    BackgroundService.setOnCallStateChangedCallback((inCall) async {
      if (!mounted) return;
      await _setCallSpeechPause(inCall);
    });

    WakeWordService.instance.onWakeWordDetected = () async {
      if (speechToText.isNotListening) {
        await WakeWordService.instance.pause();
        _wakeWordPausedForSpeech = true;
        await startListening();
        // speechToText.listen() returns immediately even though the mic is still
        // listening.  Set a timeout; if no final speech result arrives within 10
        // seconds, resume the wake word detector so the user can re-trigger.
        if (_wakeWordPausedForSpeech) {
          _speechTimeout = Timer(const Duration(seconds: 10), () {
            if (_wakeWordPausedForSpeech) {
              _wakeWordPausedForSpeech = false;
              WakeWordService.instance.resume();
            }
          });
        }
      }
    };
  }

  final _logger = DebugLogger();

  Future<void> initSpeechToText() async {
    _logger.log('HomeScreen', 'Initializing speech to text');
    await speechToText.initialize();
    setState(() {});
  }

  Future<void> initTextToSpeech() async {
    _logger.log('HomeScreen', 'Initializing text to speech');
    final prefs = await SharedPreferences.getInstance();

    // Only apply saved TTS settings if user explicitly configured them.
    // Otherwise keep the platform default to preserve the original voice.
    if (prefs.getBool('tts_configured') == true) {
      final engine = prefs.getString('tts_engine');
      if (engine != null && engine.isNotEmpty) {
        try { await flutterTts.setEngine(engine); } catch (_) {}
      }

      final language = prefs.getString('tts_language') ?? 'en-US';
      try { await flutterTts.setLanguage(language); } catch (_) {}

      final voiceName = prefs.getString('tts_voice_name');
      if (voiceName != null && voiceName.isNotEmpty) {
        try {
          final voices = await flutterTts.getVoices;
          if (voices is List) {
            final match = (voices as List).firstWhere(
              (v) => v is Map && v['name'] == voiceName && v['locale'] == language,
              orElse: () => null,
            );
            if (match != null) {
              await flutterTts.setVoice(Map<String, String>.from(match as Map));
            }
          }
        } catch (_) {}
      }

      try { await flutterTts.setSpeechRate(prefs.getDouble('tts_speech_rate') ?? 0.5); } catch (_) {}
      try { await flutterTts.setPitch(prefs.getDouble('tts_pitch') ?? 1.0); } catch (_) {}
    }

    await flutterTts.setVolume(1.0);

    // When TTS finishes speaking, wait 2 seconds before re-arming the
    // wake word detector so it doesn't hear its own echo and re-trigger.
    flutterTts.setCompletionHandler(_onTtsCompletion);

    // Track how far the engine has read into the current utterance. A
    // pause uses this (via flutter_tts's own pause/resume) to carry on
    // from the sentence it stopped in instead of starting over.
    flutterTts.setStartHandler(() {
      _ttsProgressStart = 0;
      _ttsProgressLength = 0;
    });
    // A resume restarts the remainder of the text, so offsets start at 0
    // again and the plugin reports "continue" instead of "start".
    flutterTts.setContinueHandler(() {
      _ttsProgressStart = 0;
    });
    flutterTts.setProgressHandler((text, start, end, word) {
      _ttsProgressStart = start;
      _ttsProgressLength = text.length;
    });

    // Warm the TTS engine so the first announcement on bluetooth is not
    // truncated (the engine initializes lazily and cuts off the first
    // phoneme unless primed).
    await _warmTtsEngine();
  }

  Future<void> _warmTtsEngine() async {
    try {
      // Speak silently to prime the TTS engine's audio pipeline.
      await flutterTts.setVolume(0.0);
      await flutterTts.speak("warmup");
      await Future.delayed(const Duration(milliseconds: 400));
      await flutterTts.setVolume(1.0);
    } catch (_) {}
  }

  void _onTtsCompletion() {
    // If an announcement completer is pending, complete it first. This also
    // covers an utterance that finished in the instant before a pause began:
    // the waiter is released instead of being replayed on resume.
    if (_announceCompleter != null && !_announceCompleter!.isCompleted) {
      _announceCompleter!.complete();
      return;
    }
    // Paused (user or phone call): stop here without advancing, so the
    // current chunk stays put and resume replays it from its start.
    if (_ttsEnginePaused) return;
    // Speak the next chunk of a long response, if any.
    if (_responseChunkIndex < _responseChunks.length - 1) {
      _responseChunkIndex++;
      flutterTts.speak(_responseChunks[_responseChunkIndex]);
      return;
    }
    _clearResponseChunks();
    if (_wakeWordPausedForSpeech) {
      Future.delayed(const Duration(seconds: 2), () {
        if (_wakeWordPausedForSpeech) {
          _wakeWordPausedForSpeech = false;
          WakeWordService.instance.resume();
        }
      });
    }
  }

  Future<void> systemSpeak(String content) async {
    if (_speechPaused) {
      _logger.verbose('HomeScreen', 'Holding response speech (paused)');
      return;
    }
    _logger.verbose('HomeScreen', 'Speaking response (${content.length} chars)');
    _armWakeWhileSpeaking();
    // Always go through the chunk list, even for a single short reply:
    // a pause mid-reply then resumes at the chunk we stopped on instead
    // of losing the tail of the answer.
    _responseChunks = _splitAtSentences(content, _maxTtsChunkSize);
    _responseChunkIndex = 0;
    _responseSpeechActive = true;
    if (_responseChunks.length > 1) {
      _logger.verbose('HomeScreen', 'Chunking response into ${_responseChunks.length} parts');
    }
    await flutterTts.speak(_responseChunks[0]);
  }

  void _clearResponseChunks() {
    _responseChunks = [];
    _responseChunkIndex = 0;
    _responseSpeechActive = false;
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

  // --- Voice commands ---

  String? _detectVoiceCommand(String text) {
    final lower = text.toLowerCase().trim();
    if (lower.startsWith('remember ')) return 'remember';
    if (lower == 'remember that') return 'remember_last';
    if (lower.startsWith('forget ')) return 'forget';
    if (lower == 'what do you remember' || lower == 'what do you remember about me' || lower == 'list memories') return 'recall';
    if (lower == 'clear my memories' || lower == 'forget everything') return 'clear_memories';
    if (RegExp(r'^(?:start|begin|open)?\s*(?:a\s+|another\s+)?new\s+(?:conversation|chat|session)(?:\s+please)?\s*$')
        .hasMatch(lower)) {
      return 'new_conversation';
    }
    if (lower.startsWith('local search') ||
        lower.startsWith('ask my documents')) {
      return 'local_search';
    }
    // Must come before the web-search keywords below: "private search"
    // also contains the word "search".
    if (lower.startsWith('private search')) return 'private_search';
    // Re-ask the last question with the second-opinion model.
    if (lower == 'second opinion' ||
        lower == 'another opinion' ||
        lower == 'other opinion' ||
        lower.startsWith('second opinion ') ||
        lower.startsWith('get a second opinion') ||
        lower.startsWith('give me a second opinion') ||
        lower.startsWith('give it a second opinion')) {
      return 'second_opinion';
    }
    // Re-speak what is on the response card, like the speaker icon.
    if (lower == 'replay' ||
        lower == 'replay that' ||
        lower == 'replay it' ||
        lower.startsWith('replay ')) {
      return 'replay';
    }
    if (lower.contains('weather') || lower == 'forecast') return 'weather';
    // Explicit search keywords only. Word boundaries so "research" does not match.
    if (lower == 'find' ||
        lower == 'search' ||
        lower == 'web search' ||
        lower == 'search the web' ||
        lower.startsWith('find ') ||
        lower.startsWith('search for ') ||
        lower.startsWith('search ') ||
        lower.startsWith('google ') ||
        lower.startsWith('look up ') ||
        RegExp(r'\b(search|duckduckgo|duck\s+duck\s+go|look\s+up)\b').hasMatch(lower)) {
      return 'web_search';
    }
    return null;
  }

  bool _hasLocalSearchPrefix(String text) {
    final lower = text.trim().toLowerCase();
    return lower.startsWith('local search') ||
        lower.startsWith('ask my documents') ||
        lower.startsWith('private search');
  }

  String _localSearchQuestion(String text) {
    final trimmed = text.trim();
    final lower = trimmed.toLowerCase();
    for (final prefix in ['local search', 'ask my documents', 'private search']) {
      if (lower.startsWith(prefix)) {
        var rest = trimmed.substring(prefix.length);
        rest = rest.replaceFirst(RegExp(r'^[\s,:;\-–]+'), '');
        rest = rest.replaceFirst(RegExp(r'[\s,.;:!?–-]+$'), '');
        if (rest.trim().isEmpty) return '';
        return rest.trim();
      }
    }
    return '';
  }

  Future<bool> _handleVoiceCommand(String text, {bool fromTyped = false}) async {
    final cmd = _detectVoiceCommand(text);
    if (cmd == null) return false;

    final lower = text.toLowerCase().trim();
    await MemoryService.instance.load();

    switch (cmd) {
      case 'remember':
        final content = text.substring('remember '.length).trim();
        if (content.isNotEmpty) {
          await MemoryService.instance.addEntry(content);
          await _speakAndWait('Saved');
        }
        break;
      case 'remember_last':
        if (_lastAiResponse.isNotEmpty) {
          await MemoryService.instance.addEntry(_lastAiResponse);
          await _speakAndWait('Saved');
        }
        break;
      case 'forget':
        final query = text.substring('forget '.length).trim();
        if (query.isNotEmpty) {
          final count = await MemoryService.instance.forgetByContent(query);
          await _speakAndWait(count > 0 ? 'Forgotten $count memories' : 'Nothing found to forget');
        }
        break;
      case 'recall':
        final all = MemoryService.instance.entries;
        if (all.isEmpty) {
          await _speakAndWait('No memories yet');
        } else {
          final top = all.take(3).map((e) => e.content).join('. ');
          await _speakAndWait('I remember: $top');
        }
        break;
      case 'clear_memories':
        await MemoryService.instance.clearAll();
        await _speakAndWait('All memories cleared');
        break;
      case 'new_conversation':
        await _newConversation();
        await _speakAndWait("New conversation started");
        break;
      case 'replay':
        if (generatedContent == null || generatedContent!.isEmpty) {
          await _speakAndWait('Nothing to replay yet.');
        } else {
          systemSpeak(generatedContent!);
        }
        break;
      case 'weather':
        final weatherReport = await WeatherService.instance.fetchWeather();
        await _speakAndWait(weatherReport);
        break;
      case 'local_search':
        await _handleLocalSearchCommand(text);
        break;
      case 'private_search':
        await _handleLocalSearchCommand(text, scope: 'private');
        break;
      case 'second_opinion':
        await _sendSecondOpinion();
        break;
      case 'web_search':
        final prefs = await SharedPreferences.getInstance();
        if (!(prefs.getBool('web_search_enabled') ?? false)) {
          await _speakAndWait("Web search is not enabled in settings.");
          if (!fromTyped) startListening();
          return true;
        }
        setState(() {
          _browserMode = true;
        });
        _browserFlow.tts = flutterTts;
        _browserFlow.logger = _logger;
        final initialQuery = BrowserFlow.extractSearchQuery(text);
        _logger.log('HomeScreen',
            'Entering web search mode (query=$initialQuery${fromTyped ? ', typed' : ''})');
        // Typed entry must not yank the microphone open — the user is
        // typing, and the flow accepts their next typed line anyway.
        void Function() resumeMic = () {
          if (!fromTyped) startListening();
        };
        await _browserFlow.start(
          onSpeak: (msg) => _speakAndWait(msg),
          onListeningStarted: resumeMic,
          onIdle: () {
            _browserMode = false;
            setState(() {});
            resumeMic();
          },
          onError: (msg) async {
            await _speakAndWait(msg);
            resumeMic();
          },
          initialQuery: initialQuery,
        );
        break;
    }
    if (cmd != 'web_search') {
      if (_browserMode) {
        setState(() {
          _browserMode = false;
        });
      }
      startListening();
    }
    return true;
  }

  Future<void> _handleLocalSearchCommand(String text,
      {String scope = 'public'}) async {
    // Remember the mode before the pending prompt: a bare "private
    // search" gets its question in a later turn and must stay private.
    _localSearchScope = scope;
    if (!await ResearchAssistantService.isEnabled()) {
      _localSearchTurnsRemaining = 0;
      await _speakAndWait("Local search is turned off in Settings.");
      return;
    }
    final question = _localSearchQuestion(text);
    if (question.isEmpty) {
      setState(() {
        _localSearchPending = true;
        _retryAction = null;
      });
      await _speakAndWait("What would you like me to search for.");
    } else {
      await _runLocalSearch(question, isTrigger: true);
    }
  }

  List<Map<String, String>> _recentHistoryTurns() {
    final turns = <Map<String, String>>[];
    String? pendingQuestion;
    for (final entry in _messageHistory) {
      final role = entry['role'] ?? '';
      final content = entry['content'] ?? '';
      if (role == 'user') {
        pendingQuestion = content;
      } else if (role == 'assistant' &&
          pendingQuestion != null &&
          content.isNotEmpty) {
        turns.add({'question': pendingQuestion, 'answer': content});
        pendingQuestion = null;
      }
    }
    if (turns.length > 3) {
      return turns.sublist(turns.length - 3);
    }
    return turns;
  }

  Future<void> _runLocalSearch(String question,
      {bool isTrigger = false, String scope = ''}) async {
    final searchScope = scope.isNotEmpty ? scope : _localSearchScope;
    if (isTrigger) _localSearchScope = searchScope;
    _logger.log(
        'LocalSearch', 'Running search scope=$searchScope trigger=$isTrigger');
    if (!await ResearchAssistantService.isEnabled()) {
      _localSearchTurnsRemaining = 0;
      await _speakAndWait("Local search is turned off in Settings.");
      return;
    }
    var trimmed = _localSearchQuestion(question);
    if (!_hasLocalSearchPrefix(question)) {
      trimmed = question.trim();
    }
    if (trimmed.isEmpty) {
      setState(() {
        _localSearchPending = true;
        _retryAction = null;
      });
      await _speakAndWait("What would you like me to search for.");
      return;
    }
    setState(() {
      isLoading = true;
      _retryAction = null;
    });
    final localTimer = Stopwatch()..start();
    final reachable = await ResearchAssistantService.instance.checkReachable();
    if (!reachable) {
      const message =
          "Your computer is not reachable. Check that it is on and on the "
          "same wifi, then try again.";
      setState(() {
        generatedContent = message;
        isLoading = false;
        _retryAction = () => _runLocalSearch(trimmed,
            isTrigger: isTrigger, scope: searchScope);
      });
      await _speakAndWait(message);
      return;
    }
    final result = await ResearchAssistantService.instance
        .ask(trimmed, history: _recentHistoryTurns(), scope: searchScope);
    localTimer.stop();
    final answerScreen = _localSearchScreenText(result);
    final answerSpoken = _localSearchSpeech(result);
    // Name the mode back to the user on a private search.
    final privateOk = result.ok && searchScope == 'private';
    final screenText = privateOk
        ? 'Private search, answered locally.\n\n$answerScreen'
        : answerScreen;
    final spoken =
        privateOk ? 'Private search, answered locally. $answerSpoken' : answerSpoken;
    setState(() {
      generatedContent = screenText;
      isLoading = false;
      _retryAction = result.ok
          ? null
          : () => _runLocalSearch(trimmed,
              isTrigger: isTrigger, scope: searchScope);
      if (result.ok && isTrigger) {
        _localSearchTurnsRemaining = 3;
      }
    });
    if (result.ok && (result.answer ?? '').trim().isNotEmpty) {
      _lastAiResponse = screenText;
      _previousUserQuery = trimmed;
      _previousAiResponse = screenText;
      _messageHistory.add({'role': 'user', 'content': trimmed});
      _messageHistory.add({'role': 'assistant', 'content': screenText});
      conversationService.addEntry(ConversationEntry(
        userQuery: trimmed,
        aiResponse: screenText,
        model: result.model.isNotEmpty ? result.model : 'local search',
        provider: result.provider.isNotEmpty ? result.provider : 'local search',
        routingCategory:
            searchScope == 'private' ? 'private_search' : 'local_search',
        responseTime: localTimer.elapsed,
      ));
      try {
        await conversationService.autoSave();
      } catch (_) {
        _logger.log('LocalSearch', 'Conversation auto-save failed');
      }
    }
    if (spoken.length <= _maxTtsChunkSize) {
      await _speakAndWait(spoken);
    } else {
      for (final chunk in _splitAtSentences(spoken, _maxTtsChunkSize)) {
        await _speakAndWait(chunk);
      }
    }
  }

  String _localSearchSourceLine(LocalSearchSource source) {
    return [
      source.folder,
      source.title,
      source.location,
    ].where((part) => part.trim().isNotEmpty).join(', ');
  }

  String _localSearchExcerpt(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.length <= 400) return trimmed;
    final cut = trimmed.substring(0, 400);
    final lastSpace = cut.lastIndexOf(' ');
    final head = lastSpace > 300 ? cut.substring(0, lastSpace) : cut;
    return '${head.trimRight()}...';
  }

  String _localSearchSpeech(LocalSearchResult result) {
    if (!result.ok) return result.error;
    final buffer = StringBuffer(result.answer ?? '');
    if (result.sources.isNotEmpty) {
      buffer.write(' Sources: ');
      for (var i = 0; i < result.sources.length; i++) {
        final source = result.sources[i];
        buffer.write(
            'Source ${i + 1}: ${_localSearchSourceLine(source)}. ');
        final excerpt = _localSearchExcerpt(source.text);
        if (excerpt.isNotEmpty) {
          buffer.write('Passage: $excerpt ');
        }
      }
    }
    return buffer.toString();
  }

  String _localSearchScreenText(LocalSearchResult result) {
    if (!result.ok) return result.error;
    final buffer = StringBuffer(result.answer ?? '');
    if (result.sources.isNotEmpty) {
      buffer.write('\n\nSources:');
      for (var i = 0; i < result.sources.length; i++) {
        final source = result.sources[i];
        buffer.write('\n${i + 1}. ${_localSearchSourceLine(source)}');
        final excerpt = _localSearchExcerpt(source.text);
        if (excerpt.isNotEmpty) {
          buffer.write('\n   Passage: $excerpt');
        }
      }
    }
    return buffer.toString();
  }

  // --- Search Helper ---
  
  Future<void> _handleReadingSequentialEnd() async {
    if (!_readingAllSequentially) {
      await _speakAndWait("End of snippet. Say a number to open another, 'read all', 'new search', or 'cancel'.");
      setState(() {
        _searchState = SearchState.showingResults;
      });
      return;
    }

    final nextIndex = _selectedResultIndex + 1;
    if (nextIndex < _searchResults.length) {
      await _speakAndWait("End of result. Moving to the next result. Say 'skip' to skip, or 'cancel'.");
      
      // We need to wait for a command here. 
      // Since we are in a sequence, we'll trigger a listening window.
      startListening(); 
      // Note: the actual result processing happens in onSpeechResult, 
      // so we just need to handle 'skip' and 'cancel' there.
    } else {
      await _speakAndWait("You have reached the end of the search results.");
      setState(() {
        _readingAllSequentially = false;
        _searchState = SearchState.idle;
      });
    }
  }

  String _classifyQuery(String query) {
    final lower = query.toLowerCase();
    final coding = RegExp(r'\b(code|function|bug|debug|python|javascript|dart|java|swift|typescript'
        r'|implement|algorithm|error|fix|compile|syntax|api|class|method|variable)\b');
    final quick = RegExp(r'\b(what is|who is|when|where|how many|how much|define|weather'
        r'|time|date|temperature|capital|population|meaning|synonym)\b');
    final creative = RegExp(r'\b(write|story|poem|describe|create|imagine|tell me about'
        r'|suggest|idea|draft|compose|generate|essay|letter|email)\b');

    if (coding.hasMatch(lower)) return 'coding';
    if (quick.hasMatch(lower)) return 'quick';
    if (creative.hasMatch(lower)) return 'creative';
    return 'reasoning';
  }

  Future<({String providerId, String model, String routingCategory})> _resolveRoute(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final autoRoute = prefs.getBool('auto_route_enabled') ?? false;
    if (!autoRoute) {
      final pid = await getSelectedProviderId();
      final m = await getModel();
      return (providerId: pid, model: m, routingCategory: 'manual');
    }
    final category = _classifyQuery(query);
    final pid = await getRoutingProviderId(category);
    final m = await getRoutingModel(category);
    final resolvedPid = pid.isNotEmpty ? pid : await getSelectedProviderId();
    final resolvedModel = m.isNotEmpty ? m : (await getModel());
    return (providerId: resolvedPid, model: resolvedModel, routingCategory: category);
  }

  Future<void> _speakAndWait(String text) {
    final gen = _speakGen;
    final next = _speakChain
        .then((_) => _speakNow(text, gen))
        .catchError((Object e) {
      _logger.log('HomeScreen', 'Speech failed: $e');
    });
    _speakChain = next;
    return next;
  }

  Future<void> _speakNow(String text, int gen) async {
    // Superseded by a barge-in while queued — drop it.
    if (gen != _speakGen) return;
    // Paused (user button or phone call): say nothing and release the
    // caller, so a held prompt can never stall a later flow.
    if (_speechPaused) {
      _logger.verbose('HomeScreen', 'Holding speech while paused (${text.length} chars)');
      return;
    }
    _armWakeWhileSpeaking();
    final completer = Completer<void>();
    _announceCompleter = completer;
    _pendingSpokenText = text;
    try {
      await flutterTts.speak(text);
      await _awaitTtsCompletion(completer, _speakTimeoutFor(text));
    } on TimeoutException {
      // Completion never arrived (speech was stopped/interrupted). Continue
      // instead of stalling the whole flow for a minute.
      _logger.log('HomeScreen', 'TTS completion timeout (${text.length} chars) — continuing');
    } finally {
      _pendingSpokenText = null;
      if (identical(_announceCompleter, completer)) {
        _announceCompleter = null;
      }
    }
  }

  Duration _speakTimeoutFor(String text) {
    // Observed TTS rate can be as slow as ~10 chars/second; scale with length.
    final seconds = (30 + text.length ~/ 5).clamp(60, 150);
    return Duration(seconds: seconds);
  }

  /// Waits for the completion callback in short slices, so a pause can hold
  /// an utterance open without eating into its timeout budget.
  Future<void> _awaitTtsCompletion(Completer<void> completer, Duration timeout) async {
    var deadline = DateTime.now().add(timeout);
    while (true) {
      if (completer.isCompleted) return;
      var wait = deadline.difference(DateTime.now());
      if (wait <= Duration.zero) {
        throw TimeoutException('TTS completion timed out');
      }
      if (wait > _ttsWaitSlice) wait = _ttsWaitSlice;
      try {
        await completer.future.timeout(wait);
        return;
      } on TimeoutException {
        // While paused no audio is playing, so give that time back instead
        // of letting a long pause run the utterance into a timeout.
        if (_speechPaused && !completer.isCompleted) {
          deadline = deadline.add(wait);
        }
      }
    }
  }

  bool get _speechPaused => _speechPausedByUser || _speechPausedByCall;

  /// Stops the TTS engine when a pause cause appears, or restarts whatever
  /// the pause cut off once every cause is gone. Idempotent.
  Future<void> _syncSpeechPause() async {
    if (_speechPaused) {
      if (_ttsEnginePaused) return;
      _ttsEnginePaused = true;
      final at = _ttsProgressStart;
      final of = _ttsProgressLength;
      _logger.log('HomeScreen',
          'Speech paused (user=$_speechPausedByUser, call=$_speechPausedByCall) at char $at of $of');
      // pause(), unlike stop(), remembers the text it has not read yet, so
      // the re-speak below picks up inside the sentence it stopped in
      // instead of starting the whole reply over. Engines that never report
      // progress leave that position at 0 and resume from the top of the
      // current paragraph (the reply is split into ~600-character parts).
      try {
        await flutterTts.pause();
      } catch (_) {
        try {
          await flutterTts.stop();
        } catch (_) {}
      }
      return;
    }
    if (!_ttsEnginePaused) return;
    _ttsEnginePaused = false;
    _logger.log('HomeScreen', 'Speech resumed');
    // Re-speak the exact string that was handed to the engine before the
    // pause: flutter_tts matches on it and continues from the text it had
    // not read yet. The awaited utterance comes first, otherwise the
    // response part we stopped on.
    if (_announceCompleter != null &&
        !_announceCompleter!.isCompleted &&
        _pendingSpokenText != null) {
      try {
        await flutterTts.speak(_pendingSpokenText!);
      } catch (e) {
        _logger.error('HomeScreen', 'Speech resume failed', e);
      }
      return;
    }
    if (_responseSpeechActive &&
        _responseChunks.isNotEmpty &&
        _responseChunkIndex < _responseChunks.length) {
      try {
        await flutterTts.speak(_responseChunks[_responseChunkIndex]);
      } catch (e) {
        _logger.error('HomeScreen', 'Speech resume failed', e);
      }
    }
  }

  /// Notification "Pause Speech" / "Resume Speech" button.
  Future<void> _toggleSpeechPauseByUser() async {
    if (_speechPausedByCall) {
      _logger.verbose('HomeScreen', 'Speech toggle ignored — a phone call holds the pause');
      return;
    }
    _speechPausedByUser = !_speechPausedByUser;
    await _syncSpeechPause();
    await BackgroundService.setTtsPausedState(_speechPaused);
  }

  /// Called when the phone starts or ends a call: hold speech, then let it
  /// pick up where it left off when the call is over.
  Future<void> _setCallSpeechPause(bool inCall) async {
    if (inCall == _speechPausedByCall) return;
    _speechPausedByCall = inCall;
    _logger.log('HomeScreen', inCall ? 'Phone call started — holding speech' : 'Phone call ended — releasing speech');
    await _syncSpeechPause();
    await BackgroundService.setTtsPausedState(_speechPaused);
  }

  /// Called when the user speaks while the app is talking: release the
  /// current wait, stop TTS, and drop any queued speech.
  Future<void> _interruptSpeech() async {
    _speakGen++;
    _clearResponseChunks();
    // Kill any in-flight article chunk chain — the user is taking over.
    _browserFlow.invalidateReading();
    final pending = _announceCompleter;
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
    try {
      await flutterTts.stop();
    } catch (_) {}
  }

  /// Re-arm the wake word while a reply is being spoken so the user can
  /// interrupt a long answer with "hey rhasspy". The 2-second delay gives
  /// the just-finished listening turn time to settle, and matches the
  /// echo guard used when speech finishes. The wake handler itself only
  /// acts when the mic is not already listening, so this cannot steal the
  /// microphone from an active recognition session.
  void _armWakeWhileSpeaking() {
    if (!_wakeWordPausedForSpeech) return;
    Future.delayed(const Duration(seconds: 2), () {
      if (_wakeWordPausedForSpeech) {
        _wakeWordPausedForSpeech = false;
        WakeWordService.instance.resume();
        _logger.verbose('HomeScreen', 'Wake word re-armed during speech');
      }
    });
  }

  Future<void> _speakProviderAnnouncement(SharedPreferences prefs) async {
    final currentId = prefs.getString('api_provider') ?? 'openrouter';
    final provider = apiProviders.firstWhere(
      (p) => p.id == currentId,
      orElse: () => apiProviders.first,
    );
    final model = prefs.getString('api_model') ?? provider.defaultModel;
    var text = "${provider.name}, $model";
    final braveOn = prefs.getBool('brave_search_enabled') ?? false;
    if (braveOn) {
      text += ", Brave Search On";
    }
    await _speakAndWait(text);
  }

  Future<void> startListening() async {
    _logger.log('HomeScreen', 'Starting voice listening');
    lastWords = '';
    // Fresh listening turn — abandon any pending stitch confirmation.
    _stitchTimer?.cancel();
    _stitchTimer = null;
    _stitchConfirming = false;
    _stitchAction = null;
    _stitchBase = '';
    _stitchSession = '';
    _stitchRelistens = 0;
    _confirmedThisTurn = false;
    _stitchFinishing = false;

    // Stop any previous session before starting a new one to prevent
    // speechToText from getting stuck after repeated use.
    if (speechToText.isListening) {
      await speechToText.stop();
    }
    if (!speechToText.isAvailable) {
      await speechToText.initialize();
    }

    // Stop any ongoing TTS so the mic gets a quiet room. An awaited
    // utterance (prompt, local search answer) is interrupted properly:
    // its completion waiter is released and any queued chunks are
    // dropped, so the waiting flow continues instead of stalling.
    if (_announceCompleter != null) {
      _logger.verbose('HomeScreen',
          'Barge-in — stopping awaited speech so the mic can listen');
      await _interruptSpeech();
    } else {
      // Also bump the generation: a queued chunk can slip in during the
      // microtask gap between two awaited utterances, and this drops it.
      _speakGen++;
      _clearResponseChunks();
      await flutterTts.stop();
    }

    // The microphone wins: release a pause the user pressed, so the
    // "Listening" prompt and the answer are audible again. A pause held
    // by a phone call stays in force — a call still outranks the mic.
    if (_speechPausedByUser) {
      _speechPausedByUser = false;
      await _syncSpeechPause();
      await BackgroundService.setTtsPausedState(_speechPaused);
    }

    setState(() {
      _micReallyListening = true;
    });

    final prefs = await SharedPreferences.getInstance();
    final announceMode = prefs.getInt('mic_announcement_mode') ?? 0;
    if (announceMode == 1) {
      await _speakAndWait("Listening");
    } else if (announceMode == 2) {
      await _speakProviderAnnouncement(prefs);
    }

    final listenSec = prefs.getInt('listening_duration_seconds') ?? 60;
    final pauseSec = prefs.getInt('pause_duration_seconds') ?? 12;
    _listenSec = listenSec;
    _pauseSec = pauseSec;
    _lastSpeechAt = DateTime.now();

    await speechToText.listen(
      onResult: onSpeechResult,
      listenFor: Duration(seconds: listenSec),
      pauseFor: Duration(seconds: pauseSec),
    );
    // Speech timed out or was stopped — reset state
    setState(() {
      _micReallyListening = false;
    });
  }

  Future<void> stopListening() async {
    _speechTimeout?.cancel();
    _speechTimeout = null;
    // Manual stop during a stitch window means "send what I have now".
    if (_stitchConfirming) {
      _finishStitchConfirm();
    }
    _logger.log('HomeScreen', 'Stopped listening - words detected: ${lastWords.length > 0}');
    await speechToText.stop();
    setState(() {
      _micReallyListening = false;
    });

    // Do NOT call sendMessageToOpenRouter here - onSpeechResult handles final results
    // Calling it here creates an infinite loop (stop triggers final onResult, which calls it again)

    // If wake word was paused but no speech result was processed (stop was manual), resume.
    if (_wakeWordPausedForSpeech) {
      _wakeWordPausedForSpeech = false;
      await WakeWordService.instance.resume();
    }
  }

  void onSpeechResult(SpeechRecognitionResult result) async {
    if (_stitchFinishing) {
      return;
    }

    if (_stitchConfirming) {
      _handleStitchResult(result);
      return;
    }

    if (!result.finalResult && result.recognizedWords.isNotEmpty) {
      _lastSpeechAt = DateTime.now();
    }

    setState(() {
      lastWords = result.recognizedWords;
    });


    if (result.finalResult && lastWords.isNotEmpty) {
      _logger.log('HomeScreen', 'Final speech result: "${lastWords.substring(0, lastWords.length > 50 ? 50 : lastWords.length)}${lastWords.length > 50 ? '...' : ''}"');
      _speechTimeout?.cancel();
      _speechTimeout = null;

      // Barge-in: stop whatever the app was saying so prompts can't
      // orphan each other's completion waiters.
      await _interruptSpeech();

      if (_needsStitchConfirm()) {
        _beginStitchConfirm(() async {
          await _processSpeech();
        });
      } else {
        await _processSpeech();
      }
    }
  }

  // True when this utterance may have been cut short by the phone's
  // early end-of-speech detection and should be stitched with any
  // continuation before we act on it.
  bool _needsStitchConfirm() {
    if (_browserMode) return false;
    // "New conversation" must act immediately like the button.
    if (_detectVoiceCommand(lastWords) == 'new_conversation') return false;
    final wordCount = lastWords.trim().split(RegExp(r'\s+')).length;
    // One or two words cannot be split by a mid-utterance pause.
    if (wordCount < 3) return false;
    if (_searchState == SearchState.awaitingQuery) return true;
    if (_localSearchPending) return true;
    // Results/reading dialogs expect short replies (cancel, read all, 1-9)
    // which must stay instant.
    if (_searchState != SearchState.idle) return false;
    if (_isConfirming) return false;
    return true;
  }

  void _beginStitchConfirm(void Function() action) {
    final silence = DateTime.now().difference(_lastSpeechAt);
    // 15% margin: if the speech service actually honored pauseFor, the
    // final result arrives right at the limit minus detection jitter.
    if (silence.inMilliseconds >= _pauseSec * 850) {
      _logger.log('HomeScreen', 'Silence of ${silence.inSeconds}s already >= ~$_pauseSec s — dispatching without stitch');
      _confirmedThisTurn = true;
      action();
      return;
    }
    _stitchFinishing = false;
    _stitchConfirming = true;
    _stitchBase = lastWords;
    _stitchSession = '';
    _stitchAction = action;
    _stitchRelistens = 0;
    _lastSpeechAt = DateTime.now();
    _logger.log('HomeScreen', 'Possible early cut — stitching (window $_pauseSec s) for: "${_clipWords(lastWords)}"');
    _resetStitchTimer();
    _stitchRelisten();
  }

  void _resetStitchTimer() {
    _stitchTimer?.cancel();
    _stitchTimer = Timer(Duration(seconds: _pauseSec), _finishStitchConfirm);
  }

  Future<void> _stitchRelisten() async {
    if (!_stitchConfirming || _stitchRelistens >= _maxStitchRelistens) return;
    _stitchRelistens++;
    await Future.delayed(const Duration(milliseconds: 100));
    if (!_stitchConfirming) return;
    try {
      if (speechToText.isListening) {
        // The final result can arrive while the session is still winding
        // down. Give it a moment; the timer still governs if it never ends.
        await Future.delayed(const Duration(milliseconds: 300));
        if (!_stitchConfirming || speechToText.isListening) return;
      }
      if (mounted) {
        setState(() {
          _micReallyListening = true;
        });
      }
      await speechToText.listen(
        onResult: onSpeechResult,
        listenFor: Duration(seconds: _listenSec),
        pauseFor: Duration(seconds: _pauseSec),
      );
      if (mounted) {
        setState(() {
          _micReallyListening = false;
        });
      }
    } catch (e) {
      _logger.log('HomeScreen', 'Stitch re-listen failed: $e');
    }
  }

  void _finishStitchConfirm() {
    if (!_stitchConfirming) return;
    final action = _stitchAction;
    var words = _stitchBase;
    if (_stitchSession.isNotEmpty) {
      words = words.isEmpty ? _stitchSession : '$words $_stitchSession';
    }
    if (words.isEmpty) words = lastWords;
    _stitchConfirming = false;
    _stitchAction = null;
    _stitchTimer?.cancel();
    _stitchTimer = null;
    _stitchRelistens = 0;
    _stitchBase = '';
    _stitchSession = '';
    _confirmedThisTurn = true;
    // Suppress any stray result the cancel below might still deliver.
    _stitchFinishing = true;
    _logger.log('HomeScreen', 'Stitch finished after silence: "${_clipWords(words)}"');
    try {
      if (speechToText.isListening) {
        speechToText.cancel();
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        lastWords = words;
        _micReallyListening = false;
      });
    } else {
      lastWords = words;
    }
    if (action != null) {
      action();
    }
  }

  void _handleStitchResult(SpeechRecognitionResult result) {
    if (result.finalResult) {
      final chunk =
          result.recognizedWords.isNotEmpty ? result.recognizedWords : _stitchSession;
      if (chunk.isNotEmpty && !_stitchBase.endsWith(chunk)) {
        _stitchBase = _stitchBase.isEmpty ? chunk : '$_stitchBase $chunk';
        _lastSpeechAt = DateTime.now();
        _resetStitchTimer();
        _logger.log('HomeScreen', 'Stitch segment: "${_clipWords(_stitchBase)}"');
      }
      _stitchSession = '';
      if (mounted) {
        setState(() {
          lastWords = _stitchBase;
        });
      }
      _stitchRelisten();
      return;
    }
    if (result.recognizedWords.isNotEmpty) {
      _stitchSession = result.recognizedWords;
      _lastSpeechAt = DateTime.now();
      _resetStitchTimer();
      if (mounted) {
        setState(() {
          lastWords = _stitchBase.isEmpty
              ? _stitchSession
              : '$_stitchBase $_stitchSession';
        });
      }
    }
  }

  String _clipWords(String text) =>
      text.length > 60 ? '${text.substring(0, 60)}...' : text;

  Future<void> _processSpeech() async {
    try {
      if (_localSearchPending) {
        if (_detectVoiceCommand(lastWords) == 'new_conversation') {
          _localSearchPending = false;
          await _handleVoiceCommand(lastWords);
          return;
        }
        _localSearchPending = false;
        final lower = lastWords.toLowerCase().trim();
        if (lower == 'cancel' || lower == 'stop') {
          await _speakAndWait("Cancelled.");
          startListening();
          return;
        }
        await _runLocalSearch(lastWords, isTrigger: true);
        startListening();
        return;
      }
      if (_localSearchTurnsRemaining > 0 &&
          _detectVoiceCommand(lastWords) == null &&
          !_browserMode) {
        _localSearchTurnsRemaining--;
        _logger.log('HomeScreen',
            'Local search continuation (turns left: $_localSearchTurnsRemaining)');
        await _runLocalSearch(lastWords);
        startListening();
        return;
      }
      // Non-search voice commands (weather, memory) first — must work
      // even when browser mode is active so weather never routes to DuckDuckGo.
      final detectedCmd = _detectVoiceCommand(lastWords);
      if (detectedCmd != null && detectedCmd != 'web_search') {
        if (await _handleVoiceCommand(lastWords)) {
          if (_searchState != SearchState.idle) {
            setState(() {
              _searchState = SearchState.idle;
              _readingAllSequentially = false;
            });
          }
          return;
        }
      }

      // Handle browser flow. Returns false for free text that is not a
      // search command/number — then fall through so it goes to AI chat.
      if (_browserMode) {
        final handled = await _browserFlow.handleSpeechResult(lastWords, onNextListen: startListening);
        if (handled) {
          return;
        }
        _logger.log('HomeScreen', 'BrowserFlow unhandled — routing to AI: "$lastWords"');
        setState(() {
          _browserMode = false;
          _searchState = SearchState.idle;
          _readingAllSequentially = false;
        });
      }

      // Enter browser mode on explicit search triggers, or run other commands
      if (await _handleVoiceCommand(lastWords)) {
        if (_searchState != SearchState.idle) {
          setState(() {
            _searchState = SearchState.idle;
            _readingAllSequentially = false;
          });
        }
        return;
      }

      // Handle search state machine
        if (_searchState == SearchState.awaitingQuery) {
          setState(() {
            _searchState = SearchState.showingResults;
          });
          await _speakAndWait("Searching for ${lastWords}.");
          final results = await WebSearchService.instance.search(lastWords);
          if (results.isEmpty) {
            await _speakAndWait("No results found.");
            setState(() {
              _searchState = SearchState.idle;
            });
            startListening();
          } else {
            setState(() {
              _searchResults = results;
            });
            String list = "Found ${results.length} results. ";
            for (int i = 0; i < results.length && i < 5; i++) {
              list += "${i + 1}: ${results[i].title}. ";
            }
            list += "Say a number to open, 'read all' to hear them sequentially, 'new search', or 'cancel'.";
            await _speakAndWait(list);
            startListening();
          }
          return;
        }

      // Helper: convert number words to index (0-based)
      int? _parseNumberIndex(String lower) {
        final digitMatch = RegExp(r'^\d+$').hasMatch(lower);
        if (digitMatch) return int.parse(lower) - 1;
        const numberWords = {
          'one': 0, 'two': 1, 'three': 2, 'four': 3, 'five': 4,
          'six': 5, 'seven': 6, 'eight': 7, 'nine': 8, 'ten': 9,
          'first': 0, 'second': 1, 'third': 2,
        };
        return numberWords[lower];
      }

      if (_searchState == SearchState.showingResults) {
        final lower = lastWords.toLowerCase().trim();
        if (lower == 'cancel') {
          setState(() {
            _searchState = SearchState.idle;
            _readingAllSequentially = false;
          });
          await _speakAndWait("Search cancelled.");
          return;
        }
        if (lower == 'read all') {
          setState(() {
            _readingAllSequentially = true;
            _selectedResultIndex = 0;
            _searchState = SearchState.readingResult;
          });
          final res = _searchResults[0];
          await _speakAndWait("Reading first result: ${res.title}. ${res.snippet}");
          await _handleReadingSequentialEnd();
          return;
        }
        if (lower == 'new search' ||
            RegExp(r'\b(search|duckduckgo|duck\s+duck\s+go|look\s+up)\b').hasMatch(lower)) {
          setState(() {
            _searchState = SearchState.awaitingQuery;
          });
          await _speakAndWait("What would you like me to search for?");
          startListening();
          return;
        }
        final index = _parseNumberIndex(lower);
        if (index != null) {
          if (index >= 0 && index < _searchResults.length) {
            setState(() {
              _selectedResultIndex = index;
              _searchState = SearchState.readingResult;
            });
            final res = _searchResults[index];
            await _speakAndWait("Reading ${res.title}. ${res.snippet}");
            await _handleReadingSequentialEnd();
            return;
          }
        }
      }

      // Handle reading result state (for sequential reading)
      if (_searchState == SearchState.readingResult) {
        final lower = lastWords.toLowerCase().trim();

        // Handle number selection while reading
        final index = _parseNumberIndex(lower);
        if (index != null && index >= 0 && index < _searchResults.length) {
          setState(() {
            _selectedResultIndex = index;
          });
          final res = _searchResults[index];
          await _speakAndWait("Reading ${res.title}. ${res.snippet}");
          await _handleReadingSequentialEnd();
          return;
        }

        if (lower == 'cancel') {
          setState(() {
            _searchState = SearchState.idle;
            _readingAllSequentially = false;
          });
          await _speakAndWait("Search cancelled.");
          return;
        }
        if (lower == 'skip' && _readingAllSequentially) {
          setState(() {
            _selectedResultIndex++;
          });
          if (_selectedResultIndex < _searchResults.length) {
            final res = _searchResults[_selectedResultIndex];
            await systemSpeak("Skipping to ${res.title}. ${res.snippet}");
            await _handleReadingSequentialEnd();
          } else {
            await systemSpeak("No more results to skip to.");
            setState(() {
              _readingAllSequentially = false;
              _searchState = SearchState.idle;
            });
          }
          return;
        }
        if (lower == 'new search' ||
            RegExp(r'\b(search|duckduckgo|duck\s+duck\s+go|look\s+up)\b').hasMatch(lower)) {
          setState(() {
            _searchState = SearchState.awaitingQuery;
            _readingAllSequentially = false;
          });
          await _speakAndWait("What would you like me to search for?");
          startListening();
          return;
        }
        // If not a recognized command while reading, treat as new query
        // fall through to sendMessageToOpenRouter
      }

      // If waiting for confirmation, check for yes/no response
      if (_isConfirming) {
        final lower = lastWords.toLowerCase().trim();
        final yesPattern = RegExp(r'\b(yes|yeah|yep|sure|go ahead|correct|right|proceed|ok|okay)\b');
        final noPattern = RegExp(r'\b(no|nope|nah|wrong|not quite|clarif|rephrase|different|actually)\b');
        if (yesPattern.hasMatch(lower)) {
          _confirmQuery();
          return;
        } else if (noPattern.hasMatch(lower)) {
          _clarifyQuery();
          return;
        }
        // Ambiguous — treat as a new query
        _isConfirming = false;
        _pendingClassification = null;
        _pendingQuery = '';
      }

      // Context-aware follow-up: check if this might be a misheard query
      if (_previousUserQuery.isNotEmpty && !_isConfirming) {
        final lower = lastWords.toLowerCase().trim();
        final wordCount = lower.split(RegExp(r'\s+')).length;

        // Short queries are almost always follow-ups ("why?", "how?", "tell me more")
        final isShort = wordCount <= 4;

        // Check if query contains pronouns or reference words linking to prior context
        final hasPronoun = RegExp(r'\b(it|that|this|they|them|those|these|he|she|him|her|its)\b').hasMatch(lower);

        // Check if query contains question marks (questions about prior topic)
        final hasQuestionMark = lower.contains('?');

        // Check for shared keywords with previous AI response
        final responseWords = _previousAiResponse.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length > 4).toSet();
        final queryWords = lower.split(RegExp(r'\s+')).where((w) => w.length > 4).toSet();
        final sharedKeywords = responseWords.intersection(queryWords);
        final hasSharedContext = sharedKeywords.length >= 2;

        // If none of the above, this might be a misheard transcription — ask for clarification
        if (!isShort && !hasPronoun && !hasQuestionMark && !hasSharedContext) {
          _logger.log('HomeScreen', 'Context check: possibly misheard (no link to prior context)');
          setState(() {
            generatedContent = "I think you might be starting a new topic. Did you mean to ask about something different, or would you like to continue the previous conversation?";
          });
          systemSpeak("I think you might be starting a new topic. Did you mean to ask about something different, or would you like to continue the previous conversation?");
          return;
        }
      }

      // Fall-through: free text for the AI. Confirm first when the
      // utterance could have been cut short, unless stitching already
      // happened this turn or the text is too short to have been cut.
      final wordCount = lastWords.trim().split(RegExp(r'\s+')).length;
      if (wordCount >= 3 && !_confirmedThisTurn) {
        _beginStitchConfirm(() {
          Future.delayed(const Duration(milliseconds: 500), () {
            sendMessageToOpenRouter();
          });
        });
        return;
      }
      Future.delayed(Duration(milliseconds: 500), () {
        sendMessageToOpenRouter();
      });
    } catch (e) {
      _logger.error('HomeScreen', '_processSpeech failed', e);
    }
  }

  Future<void> sendMessageToOpenRouter() async {
    if (lastWords.isEmpty) return;

    try {
      _logger.log('HomeScreen', 'Sending to AI: "${lastWords.length > 60 ? lastWords.substring(0, 60) + "..." : lastWords}"');

      // Skip voice command check if we're in browser mode - let onSpeechResult handle it
      if (!_browserMode) {
        // Check for voice commands first
        if (await _handleVoiceCommand(lastWords)) {
          setState(() {
            isLoading = false;
          });
          return;
        }
      }
      if (!_browserMode &&
          _localSearchTurnsRemaining > 0 &&
          _detectVoiceCommand(lastWords) == null) {
        _localSearchTurnsRemaining--;
        _logger.log('HomeScreen',
            'Local search continuation (turns left: $_localSearchTurnsRemaining)');
        await _runLocalSearch(lastWords);
        return;
      }

      // Smart Free: classify query and optionally confirm before answering
      final prefs = await SharedPreferences.getInstance();
      final smartFree = prefs.getBool('smart_free_enabled') ?? false;
      if (smartFree) {
        final classifier = QueryClassifier.instance;
        final classification = await classifier.classify(
          lastWords,
          smartFreeEnabled: true,
        );

        if (classification.needsConfirmation) {
          final summary = await classifier.buildSummary(classification, lastWords);
          _logger.log('HomeScreen', 'Smart Free: confirming query (${classification.category}, research=${classification.isResearch})');
          setState(() {
            _pendingClassification = classification;
            _pendingQuery = lastWords;
            _isConfirming = true;
            generatedContent = summary;
            isLoading = false;
          });
          systemSpeak(summary);
          return;
        }

        // No confirmation needed — proceed with classification hints
        await _sendQueryToAI(lastWords, classification: classification);
        return;
      }

      await _sendQueryToAI(lastWords);
    } catch (e, st) {
      _logger.error('HomeScreen', 'sendMessageToOpenRouter failed', e);
      _logger.error('HomeScreen', 'Stack trace: $st');
      setState(() {
        generatedContent = 'Error: $e';
        isLoading = false;
        _retryAction = sendMessageToOpenRouter;
      });
    }
  }

  Future<void> _confirmQuery() async {
    final query = _pendingQuery;
    final classification = _pendingClassification;
    setState(() {
      _isConfirming = false;
      _pendingClassification = null;
      _pendingQuery = '';
      isLoading = true;
    });
    await _sendQueryToAI(query, classification: classification);
  }

  Future<void> _clarifyQuery() async {
    setState(() {
      _isConfirming = false;
      _pendingClassification = null;
      _pendingQuery = '';
      generatedContent = null;
    });
    systemSpeak("What would you like me to focus on?");
    await startListening();
  }

  Future<void> _sendQueryToAI(String query,
      {QueryClassification? classification,
      String? forceProviderId,
      String? forceModel}) async {
    final isSecondOpinion = forceModel != null;
    final responseTimer = Stopwatch()..start();
    try {
      setState(() {
        isLoading = true;
        _retryAction = null;
      });

      // Recall relevant memories
      await MemoryService.instance.load();
      final relevantMemories = MemoryService.instance.search(query);
      for (final m in relevantMemories) {
        MemoryService.instance.incrementHitCount(m.id);
      }

      // Determine route (provider + model). A second opinion always goes to
      // the model picked in Settings, never through auto-route.
      final route = isSecondOpinion
          ? (providerId: forceProviderId ?? '',
              model: forceModel!,
              routingCategory: 'second_opinion')
          : await _resolveRoute(query);
      _logger.log('HomeScreen', 'Route: ${route.providerId} / ${route.model} (routing: ${route.routingCategory})');

      // A second opinion must see the same context the first answer saw:
      // drop the trailing question/answer pair(s) so the model is not
      // anchored by the first reply. Search results are re-run inside
      // chatGPTAPI exactly as they were the first time.
      List<Map<String, String>>? secondOpinionHistory;
      if (isSecondOpinion) {
        secondOpinionHistory = List<Map<String, String>>.from(_messageHistory);
        while (secondOpinionHistory.length >= 2 &&
            secondOpinionHistory.last['role'] == 'assistant' &&
            secondOpinionHistory[secondOpinionHistory.length - 2]['role'] ==
                'user' &&
            secondOpinionHistory[secondOpinionHistory.length - 2]['content'] ==
                query) {
          secondOpinionHistory.removeLast();
          secondOpinionHistory.removeLast();
        }
      }

      final isResearch = classification?.isResearch ?? false;

      final response = await openaiService.chatGPTAPI(
        query,
        history: isSecondOpinion
            ? (secondOpinionHistory!.isNotEmpty ? secondOpinionHistory : null)
            : (_messageHistory.isNotEmpty ? _messageHistory : null),
        providerId: route.providerId,
        overrideModel: route.model,
        memories: relevantMemories.isNotEmpty ? relevantMemories : null,
        maxTokens: 2000,
        isResearch: isResearch,
      );
      responseTimer.stop();

      _logger.log('HomeScreen', 'AI response received (${response?.length ?? 0} chars)');
      if (openaiService.lastServedProviderId.isNotEmpty &&
          (openaiService.lastServedProviderId != route.providerId ||
              openaiService.lastServedModel != route.model)) {
        _logger.log('HomeScreen',
            'Served by ${openaiService.lastServedProviderId} / ${openaiService.lastServedModel} (route was ${route.providerId} / ${route.model})');
      }

      setState(() {
        if (isSecondOpinion && response != null && response.isNotEmpty) {
          // Keep the first answer on screen and show the second opinion
          // underneath it, clearly labelled with the model that wrote it.
          final header = 'Second opinion (${route.model}):';
          generatedContent =
              (generatedContent == null || generatedContent!.isEmpty)
                  ? '$header\n$response'
                  : '$generatedContent\n\n$header\n$response';
        } else if (!isSecondOpinion) {
          generatedContent = response;
        }
        isLoading = false;
        _retryAction = null;
      });
      if (isSecondOpinion && (response == null || response.isEmpty)) {
        _flashStatus('The second opinion model gave no answer');
      }

      // Log the conversation entry
      if (response != null && response.isNotEmpty) {
        _lastAiResponse = response;
        _previousUserQuery = query;
        _previousAiResponse = response;
        _messageHistory.add({'role': 'user', 'content': query});
        _messageHistory.add({'role': 'assistant', 'content': response});

        conversationService.addEntry(ConversationEntry(
          userQuery: isSecondOpinion ? 'second opinion: $query' : query,
          aiResponse: response,
          model: openaiService.lastServedModel.isNotEmpty
              ? openaiService.lastServedModel
              : route.model,
          provider: openaiService.lastServedProviderId.isNotEmpty
              ? openaiService.lastServedProviderId
              : route.providerId,
          routingCategory: route.routingCategory,
          responseTime: responseTimer.elapsed,
        ));

        // Auto-save if enabled
        try {
          await conversationService.autoSave();
        } catch (_) {
          // Silently handle auto-save errors
        }

        // Fire-and-forget TTS for AI responses to prevent hang on long text.
        systemSpeak(response);
      }
    } catch (e, st) {
      _logger.error('HomeScreen', '_sendQueryToAI failed', e);
      _logger.error('HomeScreen', 'Stack trace: $st');
      setState(() {
        if (isSecondOpinion &&
            generatedContent != null &&
            generatedContent!.isNotEmpty) {
          // Keep the first answer visible; report the failure underneath.
          generatedContent = '$generatedContent\n\nSecond opinion failed: $e';
        } else {
          generatedContent = 'Error: $e';
        }
        isLoading = false;
        _retryAction = () => _sendQueryToAI(query,
            classification: classification,
            forceProviderId: forceProviderId,
            forceModel: forceModel);
      });
    }
  }

  /// Ask the model chosen under "Second opinion" in Settings the same
  /// question again — with the same injected search results — and show its
  /// answer under the first one in the transcript.
  Future<void> _sendSecondOpinion() async {
    final query = _previousUserQuery;
    if (query.isEmpty) {
      await _speakAndWait(
          'There is no previous question to get a second opinion on.');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final soProvider = await getRoutingProviderId('second_opinion');
    final soModel = await getRoutingModel('second_opinion');
    if (soModel.isEmpty) {
      await _speakAndWait('No second opinion model is set yet. In Settings, '
          'under Model Routing, pick one for Second opinion.');
      return;
    }
    _logger.log(
        'HomeScreen', 'Second opinion requested ($soProvider / $soModel)');
    _flashStatus('Getting a second opinion...');
    // Say it out loud so the user knows the second opinion is under way
    // even with the screen off. Awaited, so the reply cannot start first.
    await _speakAndWait('Getting a second opinion...');
    QueryClassification? classification;
    final smartFree = prefs.getBool('smart_free_enabled') ?? false;
    if (smartFree) {
      classification = await QueryClassifier.instance
          .classify(query, smartFreeEnabled: true);
    }
    await _sendQueryToAI(query,
        classification: classification,
        forceProviderId: soProvider,
        forceModel: soModel);
  }

  Future<void> _sendTextMessage() async {
    var text = _textInputController.text.trim();
    if (text.isEmpty) return;

    _logger.log('HomeScreen', 'Sending typed text: "${text.length > 60 ? text.substring(0, 60) + "..." : text}"');
    _textInputController.clear();

    if (_localSearchPending) {
      _localSearchPending = false;
      final lower = text.toLowerCase();
      if (lower == 'cancel' || lower == 'stop') {
        await _speakAndWait("Cancelled.");
        return;
      }
      if (_detectVoiceCommand(text) == 'new_conversation') {
        await _handleVoiceCommand(text);
        return;
      }
      await _runLocalSearch(text, isTrigger: true);
      return;
    }
    // Short typed commands: "l s", "p s", "w s" and (inside a web
    // search) "r a" expand to their full words before detection.
    text = _expandTypedShortcuts(text);
    final textCmd = _detectVoiceCommand(text);
    if (textCmd != null && textCmd != 'web_search') {
      await _handleVoiceCommand(text, fromTyped: true);
      return;
    }
    // Mirror the voice path: while the search flow is active, typed text
    // is its input (a query, a number, 'cancel') — not a new AI chat.
    if (_browserMode) {
      final handled = await _browserFlow.handleSpeechResult(text,
          onNextListen: startListening);
      if (handled) return;
      _logger.log('HomeScreen',
          'BrowserFlow unhandled (typed) — routing to AI: "$text"');
      setState(() {
        _browserMode = false;
        _searchState = SearchState.idle;
        _readingAllSequentially = false;
      });
    }
    if (textCmd == 'web_search') {
      await _handleVoiceCommand(text, fromTyped: true);
      return;
    }
    lastWords = text;
    sendMessageToOpenRouter();
  }

  /// Typed shortcuts: "l s"/"ls" → local search, "p s"/"ps" → private
  /// search, "w s"/"ws" → web search, and inside a web search
  /// "r a"/"ra" → read all. Everything after the shortcut is kept as is,
  /// so "l s where is my passport" works like the full command.
  String _expandTypedShortcuts(String text) {
    const shortcuts = <String, String>{
      'l s': 'local search',
      'ls': 'local search',
      'p s': 'private search',
      'ps': 'private search',
      'w s': 'web search',
      'ws': 'web search',
      'r a': 'read all',
      'ra': 'read all',
    };
    for (final entry in shortcuts.entries) {
      final key = entry.key;
      if (text.length < key.length) continue;
      if (text.substring(0, key.length).toLowerCase() != key) continue;
      if (text.length > key.length &&
          !RegExp(r'\s').hasMatch(text[key.length])) continue;
      // "r a" only means something while a web search is on screen.
      if ((key == 'r a' || key == 'ra') && !_browserMode) break;
      return entry.value + text.substring(key.length);
    }
    return text;
  }

  Future<void> _manualSave() async {
    if (!conversationService.hasEntries) {
      _showSnackBar('Nothing to save yet.');
      return;
    }

    final subjectController = TextEditingController();
    final firstQuery = conversationService.entries.first.userQuery;
    subjectController.text = firstQuery.length > 40
        ? firstQuery.substring(0, 40)
        : firstQuery;

    final subject = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Save Conversation',
          style: TextStyle(color: MyAppTheme.mainFontColor),
        ),
        content: TextField(
          controller: subjectController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter a subject for this conversation',
            hintStyle: TextStyle(color: Colors.grey[500]),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: MyAppTheme.mainFontColor.withValues(alpha: 0.3),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(
                color: MyAppTheme.mainFontColor,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, subjectController.text),
            child: const Text(
              'Save',
              style: TextStyle(color: MyAppTheme.mainFontColor),
            ),
          ),
        ],
      ),
    );

    if (subject == null || subject.trim().isEmpty) return;

    try {
      final filePath = await conversationService.saveToFile(
        subject: subject.trim(),
      );
      if (mounted) {
        _showSnackBar('Saved: ${filePath.split('/').last}');
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Failed to save: $e');
      }
    }
  }

  void _shareLog() async {
    final path = _logger.getLogFilePath();
    if (path == null) {
      _showSnackBar('Log not yet initialized');
      return;
    }
    final file = File(path);
    if (!await file.exists()) {
      _showSnackBar('Log file not found');
      return;
    }
    try {
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'ARYA debug log',
      );
      _logger.log('HomeScreen', 'Log shared via system share sheet');
    } catch (e) {
      _logger.error('HomeScreen', 'Share failed', e);
      _showSnackBar('Share failed: $e');
    }
  }

  Future<void> _newConversation() async {
    // Stop whatever ARYA is reading right now. The conversation itself
    // is saved below, before the in-memory copy is cleared.
    await _interruptSpeech();
    // Forget any web search / article reading session so the next
    // utterance is treated as a brand-new AI query, not a search command.
    _browserFlow.reset();
    // Abandon any pending stitch confirmation — the query is void.
    _stitchTimer?.cancel();
    _stitchTimer = null;
    _stitchConfirming = false;
    _stitchAction = null;
    _stitchBase = '';
    _stitchSession = '';
    _stitchRelistens = 0;
    _confirmedThisTurn = false;
    try {
      await conversationService.autoSave();
    } catch (_) {
      // Silently handle auto-save errors
    }
    setState(() {
      _browserMode = false;
      _searchState = SearchState.idle;
      _readingAllSequentially = false;
      _selectedResultIndex = -1;
      _searchResults = [];
      _messageHistory.clear();
      generatedContent = null;
      lastWords = '';
      _isConfirming = false;
      _localSearchPending = false;
      _localSearchTurnsRemaining = 0;
      _localSearchScope = 'public';
      _retryAction = null;
      _pendingClassification = null;
      _pendingQuery = '';
      _previousUserQuery = '';
      _previousAiResponse = '';
      _webSearchResultsText = '';
    });
    conversationService.clear();
    _clearResponseChunks();
    _logger.log('HomeScreen', 'New conversation started — search and reading state cleared');
    _flashStatus('New conversation started');
  }

  void _flashStatus(String message) {
    _statusTimer?.cancel();
    setState(() {
      _statusMessage = message;
    });
    _statusTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() {
        _statusMessage = null;
      });
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: MyAppTheme.mainFontColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _speechTimeout?.cancel();
    _stitchTimer?.cancel();
    _statusTimer?.cancel();
    _textInputController.dispose();
    _textFocusNode.dispose();
    super.dispose();
    speechToText.stop();
    flutterTts.stop();
  }

  Widget _buildTextInputBar() {
    return Container(
      padding: EdgeInsets.only(left: 8, right: 8, top: 8, bottom: 24),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        border: Border(
          top: BorderSide(
            color: MyAppTheme.borderColor.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Mic button
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _micReallyListening
                  ? MyAppTheme.mainFontColor
                  : MyAppTheme.mainFontColor.withValues(alpha: 0.3),
            ),
            child: IconButton(
              icon: Icon(
                _micReallyListening ? Icons.mic : Icons.mic_none,
                color: Colors.white,
                size: 22,
              ),
              onPressed: () async {
                if (await speechToText.hasPermission &&
                    speechToText.isNotListening) {
                  await startListening();
                } else if (speechToText.isListening) {
                  await stopListening();
                } else {
                  initSpeechToText();
                }
              },
              tooltip: 'Microphone',
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: _textInputController,
              focusNode: _textFocusNode,
              maxLines: null,
              textInputAction: TextInputAction.newline,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'Cera Pro',
                fontSize: 15,
              ),
              decoration: InputDecoration(
                hintText: 'Type a message...',
                hintStyle: TextStyle(
                  color: Colors.grey[600],
                  fontFamily: 'Cera Pro',
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: MyAppTheme.mainFontColor,
            ),
            child: IconButton(
              icon: const Icon(
                Icons.arrow_upward,
                color: Colors.white,
                size: 22,
              ),
              onPressed: _sendTextMessage,
              tooltip: 'Send',
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // backgroundColor: Colors.grey[50],
      drawer: Drawer(
        backgroundColor: Colors.black,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                color: MyAppTheme.mainFontColor,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white.withValues(alpha: 0.3),
                    child: const Text(
                      "A",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "A.R.Y.A",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    "Adaptive Real-time Yielding Assistant",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.settings, color: MyAppTheme.mainFontColor),
              title: const Text(
                "Settings",
                style: TextStyle(color: Colors.white, fontFamily: 'Cera Pro'),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.help_outline, color: MyAppTheme.mainFontColor),
              title: const Text(
                "Help",
                style: TextStyle(color: Colors.white, fontFamily: 'Cera Pro'),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HelpScreen()),
                );
              },
            ),
          ],
        ),
      ),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        centerTitle: true,
        title: Text(
          "A R Y A",
          style: TextStyle(
            color: MyAppTheme.mainFontColor,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: 4,
            fontFamily: 'Cera Pro',
          ),
        ),
        leading: Builder(
          builder: (BuildContext context) {
            return IconButton(
              iconSize: 45,
              icon: const Icon(
                Icons.menu,
                color: MyAppTheme.mainFontColor,
                size: 28,
              ),
              onPressed: () {
                debugPrint("Menu button pressed");
                Scaffold.of(context).openDrawer();
              },
              tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.bug_report,
              color: MyAppTheme.mainFontColor,
              size: 28,
            ),
            onPressed: _shareLog,
            tooltip: 'Share debug log',
          ),
          IconButton(
            icon: const Icon(
              Icons.save_alt,
              color: MyAppTheme.mainFontColor,
              size: 28,
            ),
            onPressed: _manualSave,
            tooltip: 'Save conversation',
          ),
          IconButton(
            icon: const Icon(
              Icons.add_comment,
              color: MyAppTheme.mainFontColor,
              size: 28,
            ),
            onPressed: _newConversation,
            tooltip: 'New conversation',
          ),
          IconButton(
            icon: const Icon(
              Icons.settings,
              color: MyAppTheme.mainFontColor,
              size: 28,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
            tooltip: 'Settings',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_statusMessage != null)
            Container(
              width: double.infinity,
              color: MyAppTheme.mainFontColor.withValues(alpha: 0.2),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _statusMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Cera Pro',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Background Service toggle — quick access on home screen
                  Container(
                    margin: EdgeInsets.only(top: 8, bottom: 4, left: 20, right: 20),
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: MyAppTheme.borderColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          "Background Service",
                          style: TextStyle(
                            color: MyAppTheme.mainFontColor,
                            fontSize: 14,
                            fontFamily: 'Cera Pro',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Spacer(),
                        Text(
                          BackgroundService.isRunning ? "Running" : "Stopped",
                          style: TextStyle(
                            color: BackgroundService.isRunning
                                ? Color.fromRGBO(76, 175, 80, 1)
                                : Colors.grey,
                            fontSize: 12,
                            fontFamily: 'Cera Pro',
                          ),
                        ),
                        SizedBox(width: 8),
                        Switch(
                          value: BackgroundService.isRunning,
                          onChanged: (val) async {
                            await BackgroundService.setEnabled(val);
                            setState(() {});
                          },
                          activeColor: MyAppTheme.mainFontColor,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 8),

                  // Welcome message or Speech Recognition Display
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    margin: EdgeInsets.symmetric(horizontal: 30),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _micReallyListening
                            ? [
                                MyAppTheme.mainFontColor.withValues(alpha: 0.4),
                                MyAppTheme.secondSuggestionBoxColor.withValues(
                                  alpha: 0.3,
                                ),
                              ]
                            : [
                                MyAppTheme.firstSuggestionBoxColor.withValues(
                                  alpha: 0.3,
                                ),
                                MyAppTheme.secondSuggestionBoxColor.withValues(
                                  alpha: 0.2,
                                ),
                              ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: _micReallyListening
                            ? MyAppTheme.mainFontColor
                            : MyAppTheme.borderColor,
                        width: _micReallyListening ? 2.0 : 1.5,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: MyAppTheme.mainFontColor.withValues(
                            alpha: _micReallyListening ? 0.3 : 0.1,
                          ),
                          blurRadius: _micReallyListening ? 20 : 10,
                          spreadRadius: _micReallyListening ? 4 : 2,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                            if (_micReallyListening && lastWords.isEmpty)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.mic,
                                    color: MyAppTheme.mainFontColor,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    "Wake the mic...",
                                    style: TextStyle(
                                      color: MyAppTheme.mainFontColor,
                                      fontSize: 14,
                                      fontFamily: 'Cera Pro',
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            if (_micReallyListening && lastWords.isNotEmpty)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.transcribe,
                                    color: MyAppTheme.mainFontColor,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    "Transcribing...",
                                    style: TextStyle(
                                      color: MyAppTheme.mainFontColor,
                                      fontSize: 14,
                                      fontFamily: 'Cera Pro',
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            if (_micReallyListening) SizedBox(height: 8),
                            Text(
                              lastWords.isEmpty
                                  ? "I am ARYA. Wake the mic to speak."
                                  : lastWords,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: MyAppTheme.mainFontColor,
                            fontSize: 16,
                            fontFamily: 'Cera Pro',
                            height: 1.4,
                            fontWeight: lastWords.isEmpty
                                ? FontWeight.normal
                                : FontWeight.w600,
                          ),
                        ),
                        if (isLoading && !_micReallyListening)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: MyAppTheme.mainFontColor,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text(
                                  'Processing...',
                                  style: TextStyle(
                                    fontFamily: 'Cera Pro',
                                    fontWeight: FontWeight.w600,
                                    color: MyAppTheme.mainFontColor,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),

                  // AI Response Section
                  if (generatedContent != null)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      margin: EdgeInsets.symmetric(horizontal: 30).copyWith(top: 20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            MyAppTheme.thirdSuggestionBoxColor.withValues(alpha: 0.3),
                            MyAppTheme.firstSuggestionBoxColor.withValues(alpha: 0.2),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(
                          color: MyAppTheme.mainFontColor.withValues(alpha: 0.5),
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: MyAppTheme.mainFontColor.withValues(alpha: 0.15),
                            blurRadius: 10,
                            spreadRadius: 2,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                color: MyAppTheme.mainFontColor,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "ARYA Response:",
                                  style: TextStyle(
                                    color: MyAppTheme.mainFontColor,
                                    fontSize: 14,
                                    fontFamily: 'Cera Pro',
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.volume_up,
                                  color: MyAppTheme.mainFontColor,
                                  size: 24,
                                ),
                                onPressed: () {
                                  systemSpeak(generatedContent!);
                                },
                                tooltip: 'Replay response',
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          Text(
                            generatedContent!,
                            style: TextStyle(
                              color: MyAppTheme.mainFontColor,
                              fontSize: 15,
                              fontFamily: 'Cera Pro',
                              height: 1.5,
                            ),
                          ),
                          if (_retryAction != null) ...[
                            SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: () async {
                                final action = _retryAction;
                                if (action == null) return;
                                setState(() {
                                  _retryAction = null;
                                });
                                await action();
                              },
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text(
                                "Retry",
                                style: TextStyle(fontFamily: 'Cera Pro'),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    MyAppTheme.mainFontColor.withValues(alpha: 0.3),
                                foregroundColor: MyAppTheme.mainFontColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                                padding: EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ],
                          if (_previousUserQuery.isNotEmpty && !_isConfirming) ...[
                            SizedBox(height: _retryAction != null ? 8 : 12),
                            ElevatedButton.icon(
                              onPressed: _sendSecondOpinion,
                              icon: const Icon(Icons.compare_arrows, size: 18),
                              label: const Text(
                                "Second opinion",
                                style: TextStyle(fontFamily: 'Cera Pro'),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: MyAppTheme.mainFontColor
                                    .withValues(alpha: 0.18),
                                foregroundColor: MyAppTheme.mainFontColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                                padding: EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                  // Confirmation buttons (Smart Free)
                  if (_isConfirming)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _confirmQuery,
                              icon: const Icon(Icons.check, size: 18),
                              label: const Text(
                                "Yes, go ahead",
                                style: TextStyle(fontFamily: 'Cera Pro'),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Color.fromRGBO(76, 175, 80, 1),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                                padding: EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _clarifyQuery,
                              icon: const Icon(Icons.edit, size: 18),
                              label: const Text(
                                "No, let me clarify",
                                style: TextStyle(fontFamily: 'Cera Pro'),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: MyAppTheme.mainFontColor.withValues(alpha: 0.3),
                                foregroundColor: MyAppTheme.mainFontColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                                padding: EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  SizedBox(height: 20),
                ],
              ),
            ),
          ),
          _buildTextInputBar(),
        ],
      ),
    );
  }
}
