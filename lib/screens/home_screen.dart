import 'dart:async';
import 'dart:io';
import 'package:arya/screens/settings_screen.dart';
import 'package:share_plus/share_plus.dart';
import 'package:arya/services/api_providers.dart';
import 'package:arya/services/background_service.dart';
import 'package:arya/services/conversation_service.dart';
import 'package:arya/services/debug_logger.dart';
import 'package:arya/services/openai_service.dart';
import 'package:arya/services/wake_word_service.dart';
import 'package:arya/theme/app_theme.dart';
import 'package:arya/widgets/feature_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

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
  static const _btChannel = MethodChannel('arya.bluetooth_mic_toggle');

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
      systemSpeak(current ? "Brave Search Off" : "Brave Search On");
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

    _btChannel.setMethodCallHandler((call) async {
      if (call.method == 'toggleMic') {
        if (speechToText.isListening) {
          await stopListening();
        } else {
          await startListening();
        }
      }
    });
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

    final engine = prefs.getString('tts_engine');
    if (engine != null && engine.isNotEmpty) {
      await flutterTts.setEngine(engine);
    }

    final language = prefs.getString('tts_language') ?? 'en-US';
    await flutterTts.setLanguage(language);

    final voiceName = prefs.getString('tts_voice_name');
    if (voiceName != null && voiceName.isNotEmpty) {
      final voices = await flutterTts.getVoices;
      final match = voices.firstWhere(
        (v) => v['name'] == voiceName && v['locale'] == language,
        orElse: () => null,
      );
      if (match != null) {
        await flutterTts.setVoice(Map<String, String>.from(match));
      }
    }

    await flutterTts.setSpeechRate(prefs.getDouble('tts_speech_rate') ?? 0.5);
    await flutterTts.setPitch(prefs.getDouble('tts_pitch') ?? 1.0);
    await flutterTts.setVolume(1.0);

    // When TTS finishes speaking a response, resume wake word detection
    // if it was paused for speech.
    flutterTts.setCompletionHandler(() {
      if (_wakeWordPausedForSpeech) {
        _wakeWordPausedForSpeech = false;
        WakeWordService.instance.resume();
      }
    });
  }

  Future<void> systemSpeak(String content) async {
    _logger.verbose('HomeScreen', 'Speaking response (${content.length} chars)');
    await flutterTts.speak(content);
  }

  Future<void> startListening() async {
    _logger.log('HomeScreen', 'Starting voice listening');
    lastWords = '';
    setState(() {
      _micReallyListening = true;
    });
    await speechToText.listen(
      onResult: onSpeechResult,
      listenFor: Duration(seconds: 30),
      pauseFor: Duration(seconds: 3),
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

    // Automatically send to AI after stopping
    if (lastWords.isNotEmpty) {
      await sendMessageToOpenRouter();
    }

    // If wake word was paused but no speech result was processed (stop was manual), resume.
    if (_wakeWordPausedForSpeech) {
      _wakeWordPausedForSpeech = false;
      await WakeWordService.instance.resume();
    }
  }

  void onSpeechResult(SpeechRecognitionResult result) {
    setState(() {
      lastWords = result.recognizedWords;
    });

    if (result.finalResult && lastWords.isNotEmpty) {
      _logger.log('HomeScreen', 'Final speech result: "${lastWords.substring(0, lastWords.length > 50 ? 50 : lastWords.length)}${lastWords.length > 50 ? '...' : ''}"');
      _speechTimeout?.cancel();
      _speechTimeout = null;
      Future.delayed(Duration(milliseconds: 500), () {
        sendMessageToOpenRouter();
      });
    }
  }

  Future<void> sendMessageToOpenRouter() async {
    if (lastWords.isEmpty) return;

    _logger.log('HomeScreen', 'Sending to AI: "${lastWords.length > 60 ? lastWords.substring(0, 60) + "..." : lastWords}"');

    setState(() {
      isLoading = true;
    });

    final model = await getModel();
    _logger.log('HomeScreen', 'Using model: $model');
    final response = await openaiService.chatGPTAPI(
      lastWords,
      history: _messageHistory.isNotEmpty ? _messageHistory : null,
    );

    _logger.log('HomeScreen', 'AI response received (${response?.length ?? 0} chars)');

    setState(() {
      generatedContent = response;
      isLoading = false;
    });

    // Log the conversation entry
    if (response != null && response.isNotEmpty) {
      _messageHistory.add({'role': 'user', 'content': lastWords});
      _messageHistory.add({'role': 'assistant', 'content': response});

      conversationService.addEntry(ConversationEntry(
        userQuery: lastWords,
        aiResponse: response,
        model: model,
      ));

      // Auto-save if enabled
      try {
        await conversationService.autoSave();
      } catch (_) {
        // Silently handle auto-save errors
      }

      await systemSpeak(response);
    }

    // Resume wake word detection after the conversation cycle completes.
    if (_wakeWordPausedForSpeech) {
      _wakeWordPausedForSpeech = false;
      await WakeWordService.instance.resume();
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
          style: TextStyle(color: Color.fromRGBO(255, 87, 51, 1)),
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
                color: const Color.fromRGBO(255, 87, 51, 1).withValues(alpha: 0.3),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(
                color: Color.fromRGBO(255, 87, 51, 1),
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
              style: TextStyle(color: Color.fromRGBO(255, 87, 51, 1)),
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

  void _newConversation() {
    setState(() {
      _messageHistory.clear();
      generatedContent = null;
      lastWords = '';
    });
    conversationService.clear();
    _showSnackBar('New conversation started');
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color.fromRGBO(255, 87, 51, 1),
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
      padding: EdgeInsets.only(left: 16, right: 8, top: 8, bottom: 8),
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
              color: const Color.fromRGBO(255, 87, 51, 1),
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
                color: Color.fromRGBO(255, 87, 51, 1),
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
              leading: const Icon(Icons.settings, color: Color.fromRGBO(255, 87, 51, 1)),
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
              icon: SizedBox(
                width: 35,
                height: 35,
                child: Lottie.asset(
                  'assets/images/Fire.json',
                  fit: BoxFit.contain,
                  repeat: true,
                  animate: true,
                ),
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
              color: Color.fromRGBO(255, 87, 51, 1),
              size: 28,
            ),
            onPressed: _shareLog,
            tooltip: 'Share debug log',
          ),
          IconButton(
            icon: const Icon(
              Icons.save_alt,
              color: Color.fromRGBO(255, 87, 51, 1),
              size: 28,
            ),
            onPressed: _manualSave,
            tooltip: 'Save conversation',
          ),
          IconButton(
            icon: const Icon(
              Icons.add_comment,
              color: Color.fromRGBO(255, 87, 51, 1),
              size: 28,
            ),
            onPressed: _newConversation,
            tooltip: 'New conversation',
          ),
          IconButton(
            icon: const Icon(
              Icons.settings,
              color: Color.fromRGBO(255, 87, 51, 1),
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
                          activeColor: Color.fromRGBO(255, 87, 51, 1),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 12),
                  // Avatar with fire animation
                  Stack(
                    children: [
                      Center(
                        child: Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: MyAppTheme.mainFontColor.withValues(
                                  alpha: 0.3,
                                ),
                                blurRadius: 30,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Lottie JSON animation behind the avatar
                              Positioned.fill(
                                child: Opacity(
                                  opacity: 0.9,
                                  child: Lottie.asset(
                                    'assets/images/Fire.json',
                                    fit: BoxFit.contain,
                                    repeat: true,
                                    animate: true,
                                  ),
                                ),
                              ),

                              // Circular avatar on top
                              Positioned(
                                top: 86,
                                child: CircleAvatar(
                                  radius: 60,
                                  backgroundImage: AssetImage(
                                    'assets/images/arya-final.png',
                                  ),
                                  backgroundColor: Colors.transparent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 30),

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

                  SizedBox(height: 30),

                  // Features header
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 30),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 24,
                          decoration: BoxDecoration(
                            color: MyAppTheme.mainFontColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text(
                          "Features",
                          style: TextStyle(
                            color: MyAppTheme.mainFontColor,
                            fontSize: 20,
                            fontFamily: 'Cera Pro',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 20),

                  //features list
                  Column(
                    children: [
                      MyFeatureBox(
                        color: MyAppTheme.firstSuggestionBoxColor,
                        headerText: 'ChatGPT Integration',
                        descriptionText:
                            'Integrated ChatGPT into ARYA for intelligent conversations.',
                        icon: Icons.chat_bubble_outline,
                      ),
                      MyFeatureBox(
                        color: MyAppTheme.secondSuggestionBoxColor,
                        headerText: 'Smart Voice Assistant',
                        descriptionText:
                            'Interact with ARYA using natural language voice commands.',
                        icon: Icons.mic_outlined,
                      ),
                    ],
                  ),

                  SizedBox(height: 20),
                ],
              ),
            ),
          ),
          _buildTextInputBar(),
        ],
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: MyAppTheme.mainFontColor.withValues(alpha: 0.4),
              blurRadius: 15,
              spreadRadius: 3,
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: () async {
            debugPrint("Floating Action Button Pressed");
            if (await speechToText.hasPermission &&
                speechToText.isNotListening) {
              await startListening();
            } else if (speechToText.isListening) {
              await stopListening();
            } else {
              initSpeechToText();
            }
          },
          backgroundColor: MyAppTheme.mainFontColor,
          elevation: 0,
          child: const Icon(
            Icons.keyboard_voice,
            color: MyAppTheme.whiteColor,
            size: 28,
          ),
        ),
      ),
    );
  }
}
