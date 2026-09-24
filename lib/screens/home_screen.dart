import 'dart:async';
import 'dart:io';
import 'package:arya/models/memory_entry.dart';
import 'package:arya/screens/settings_screen.dart';
import 'package:share_plus/share_plus.dart';
import 'package:arya/services/api_providers.dart';
import 'package:arya/services/background_service.dart';
import 'package:arya/services/conversation_service.dart';
import 'package:arya/services/debug_logger.dart';
import 'package:arya/services/memory_service.dart';
import 'package:arya/services/openai_service.dart';
import 'package:arya/services/query_classifier.dart';
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
  Completer<void>? _announceCompleter;
  // Serializes speech so overlapping prompts can't orphan each other's
  // completion waiters (which caused 60-second TimeoutException stalls).
  Future<void> _speakChain = Future.value();
  // Bumped when the user barges in; queued speech from before is skipped.
  int _speakGen = 0;
  static const int _maxTtsChunkSize = 3500;
  List<String> _responseChunks = [];
  int _responseChunkIndex = 0;
  String _lastAiResponse = '';
  static const _btChannel = MethodChannel('arya.bluetooth_mic_toggle');
  QueryClassification? _pendingClassification;
  String _pendingQuery = '';
  bool _isConfirming = false;
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

  @override
  void initState() {
    super.initState();
    initSpeechToText();
    initTextToSpeech();
    BackgroundService.setOnStartMicCallback(() {
      if (speechToText.isNotListening) {
        startListening();
      }
    });

    BackgroundService.setOnNewConversationCallback(() {
      _newConversation();
      systemSpeak("New conversation started");
    });

    BackgroundService.setOnToggleBraveSearchCallback(() async {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getBool('brave_search_enabled') ?? false;
      await prefs.setBool('brave_search_enabled', !current);
      systemSpeak(current ? "You have turned off Brave Search" : "Brave Search On");
    });

    BackgroundService.setOnRotateProviderCallback(() async {
      final prefs = await SharedPreferences.getInstance();
      final currentId = prefs.getString('api_provider') ?? 'openrouter';
      final currentIndex = apiProviders.indexWhere((p) => p.id == currentId);
      final nextIndex = (currentIndex + 1) % apiProviders.length;
      final next = apiProviders[nextIndex];
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
    // If an announcement completer is pending, complete it first.
    if (_announceCompleter != null && !_announceCompleter!.isCompleted) {
      _announceCompleter!.complete();
      return;
    }
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
    _logger.verbose('HomeScreen', 'Speaking response (${content.length} chars)');
    if (content.length <= _maxTtsChunkSize) {
      _clearResponseChunks();
      await flutterTts.speak(content);
      return;
    }
    _responseChunks = _splitAtSentences(content, _maxTtsChunkSize);
    _responseChunkIndex = 0;
    _logger.verbose('HomeScreen', 'Chunking response into ${_responseChunks.length} parts');
    await flutterTts.speak(_responseChunks[0]);
  }

  void _clearResponseChunks() {
    _responseChunks = [];
    _responseChunkIndex = 0;
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
        RegExp(r'\b(search|searching|google|duckduckgo|duck\s+duck\s+go|look\s+up)\b').hasMatch(lower)) {
      return 'web_search';
    }
    return null;
  }

  Future<bool> _handleVoiceCommand(String text) async {
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
      case 'weather':
        final weatherReport = await WeatherService.instance.fetchWeather();
        await _speakAndWait(weatherReport);
        break;
      case 'web_search':
        final prefs = await SharedPreferences.getInstance();
        if (!(prefs.getBool('web_search_enabled') ?? false)) {
          await _speakAndWait("Web search is not enabled in settings.");
          startListening();
          return true;
        }
        setState(() {
          _browserMode = true;
        });
        _browserFlow.tts = flutterTts;
        _browserFlow.logger = _logger;
        final initialQuery = BrowserFlow.extractSearchQuery(text);
        _logger.log('HomeScreen', 'Entering web search mode (query=$initialQuery)');
        await _browserFlow.start(
          onSpeak: (msg) => _speakAndWait(msg),
          onListeningStarted: () {
            startListening();
          },
          onIdle: () {
            _browserMode = false;
            setState(() {});
            startListening();
          },
          onError: (msg) async {
            await _speakAndWait(msg);
            startListening();
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

  Future<({String providerId, String model})> _resolveRoute(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final autoRoute = prefs.getBool('auto_route_enabled') ?? false;
    if (!autoRoute) {
      final pid = await getSelectedProviderId();
      final m = await getModel();
      return (providerId: pid, model: m);
    }
    final category = _classifyQuery(query);
    final pid = await getRoutingProviderId(category);
    final m = await getRoutingModel(category);
    final resolvedPid = pid.isNotEmpty ? pid : await getSelectedProviderId();
    final resolvedModel = m.isNotEmpty ? m : (await getModel());
    return (providerId: resolvedPid, model: resolvedModel);
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
    final completer = Completer<void>();
    _announceCompleter = completer;
    try {
      await flutterTts.speak(text);
      await completer.future.timeout(_speakTimeoutFor(text));
    } on TimeoutException {
      // Completion never arrived (speech was stopped/interrupted). Continue
      // instead of stalling the whole flow for a minute.
      _logger.log('HomeScreen', 'TTS completion timeout (${text.length} chars) — continuing');
    } finally {
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

  /// Called when the user speaks while the app is talking: release the
  /// current wait, stop TTS, and drop any queued speech.
  Future<void> _interruptSpeech() async {
    _speakGen++;
    _clearResponseChunks();
    final pending = _announceCompleter;
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
    try {
      await flutterTts.stop();
    } catch (_) {}
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

    // Stop any previous session before starting a new one to prevent
    // speechToText from getting stuck after repeated use.
    if (speechToText.isListening) {
      await speechToText.stop();
    }
    if (!speechToText.isAvailable) {
      await speechToText.initialize();
    }

    // Stop any ongoing TTS so it doesn't get interrupted mid-sentence
    // by the announcement speech or by a new response later. Skip when a
    // prompt is mid-speech — killing it orphaned its completion waiter and
    // stalled the flow for 60 seconds.
    _clearResponseChunks();
    if (_announceCompleter == null) {
      await flutterTts.stop();
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
            RegExp(r'\b(search|searching|google|duckduckgo|duck\s+duck\s+go|look\s+up)\b').hasMatch(lower)) {
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
            RegExp(r'\b(search|searching|google|duckduckgo|duck\s+duck\s+go|look\s+up)\b').hasMatch(lower)) {
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

      Future.delayed(Duration(milliseconds: 500), () {
        sendMessageToOpenRouter();
      });
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
          final summary = classifier.buildSummary(classification, lastWords);
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

  Future<void> _sendQueryToAI(String query, {QueryClassification? classification}) async {
    try {
      setState(() {
        isLoading = true;
      });

      // Recall relevant memories
      await MemoryService.instance.load();
      final relevantMemories = MemoryService.instance.search(query);
      for (final m in relevantMemories) {
        MemoryService.instance.incrementHitCount(m.id);
      }

      // Determine route (provider + model)
      final route = await _resolveRoute(query);
      _logger.log('HomeScreen', 'Route: ${route.providerId} / ${route.model}');

      final isResearch = classification?.isResearch ?? false;

      final response = await openaiService.chatGPTAPI(
        query,
        history: _messageHistory.isNotEmpty ? _messageHistory : null,
        providerId: route.providerId,
        overrideModel: route.model,
        memories: relevantMemories.isNotEmpty ? relevantMemories : null,
        maxTokens: 2000,
        isResearch: isResearch,
      );

      _logger.log('HomeScreen', 'AI response received (${response?.length ?? 0} chars)');

      setState(() {
        generatedContent = response;
        isLoading = false;
      });

      // Log the conversation entry
      if (response != null && response.isNotEmpty) {
        _lastAiResponse = response;
        _previousUserQuery = query;
        _previousAiResponse = response;
        _messageHistory.add({'role': 'user', 'content': query});
        _messageHistory.add({'role': 'assistant', 'content': response});

        conversationService.addEntry(ConversationEntry(
          userQuery: query,
          aiResponse: response,
          model: route.model,
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
        generatedContent = 'Error: $e';
        isLoading = false;
      });
    }
  }

  void _sendTextMessage() {
    final text = _textInputController.text.trim();
    if (text.isEmpty) return;

    _logger.log('HomeScreen', 'Sending typed text: "${text.length > 60 ? text.substring(0, 60) + "..." : text}"');
    lastWords = text;
    _textInputController.clear();
    sendMessageToOpenRouter();
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
    try {
      await conversationService.autoSave();
    } catch (_) {
      // Silently handle auto-save errors
    }
    setState(() {
      _messageHistory.clear();
      generatedContent = null;
      lastWords = '';
      _isConfirming = false;
      _pendingClassification = null;
      _pendingQuery = '';
      _previousUserQuery = '';
      _previousAiResponse = '';
    });
    conversationService.clear();
    _clearResponseChunks();
    _showSnackBar('New conversation started');
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
