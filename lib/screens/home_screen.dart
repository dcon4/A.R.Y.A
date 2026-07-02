import 'package:arya/screens/settings_screen.dart';
import 'package:arya/services/conversation_service.dart';
import 'package:arya/services/openai_service.dart';
import 'package:arya/theme/app_theme.dart';
import 'package:arya/widgets/feature_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:lottie/lottie.dart';
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

  @override
  void initState() {
    super.initState();
    initSpeechToText();
    initTextToSpeech();
  }

  Future<void> initSpeechToText() async {
    await speechToText.initialize();
    setState(() {});
  }

  Future<void> initTextToSpeech() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setPitch(1.0);
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setVolume(1.0);
  }

  Future<void> systemSpeak(String content) async {
    await flutterTts.speak(content);
  }

  Future<void> startListening() async {
    await speechToText.listen(
      onResult: onSpeechResult,
      listenFor: Duration(seconds: 30),
      pauseFor: Duration(seconds: 3),
    );
    setState(() {});
  }

  Future<void> stopListening() async {
    await speechToText.stop();
    setState(() {});

    // Automatically send to AI after stopping
    if (lastWords.isNotEmpty) {
      await sendMessageToOpenRouter();
    }
  }

  void onSpeechResult(SpeechRecognitionResult result) {
    setState(() {
      lastWords = result.recognizedWords;
    });

    if (result.finalResult && lastWords.isNotEmpty) {
      debugPrint("Final result detected: $lastWords");
      Future.delayed(Duration(milliseconds: 500), () {
        sendMessageToOpenRouter();
      });
    }
  }

  Future<void> sendMessageToOpenRouter() async {
    if (lastWords.isEmpty) return;

    debugPrint("Sending to AI: $lastWords");

    setState(() {
      isLoading = true;
    });

    final model = await getModel();
    final response = await openaiService.chatGPTAPI(lastWords);

    debugPrint("AI Response received: $response");

    setState(() {
      generatedContent = response;
      isLoading = false;
    });

    // Log the conversation entry
    if (response != null && response.isNotEmpty) {
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
    super.dispose();
    speechToText.stop();
    flutterTts.stop();
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
              Icons.save_alt,
              color: Color.fromRGBO(255, 87, 51, 1),
              size: 28,
            ),
            onPressed: _manualSave,
            tooltip: 'Save conversation',
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
      body: SingleChildScrollView(
        child: Column(
          children: [
            SizedBox(height: 20),
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
                  colors: speechToText.isListening
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
                  color: speechToText.isListening
                      ? MyAppTheme.mainFontColor
                      : MyAppTheme.borderColor,
                  width: speechToText.isListening ? 2.0 : 1.5,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: MyAppTheme.mainFontColor.withValues(
                      alpha: speechToText.isListening ? 0.3 : 0.1,
                    ),
                    blurRadius: speechToText.isListening ? 20 : 10,
                    spreadRadius: speechToText.isListening ? 4 : 2,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  if (speechToText.isListening)
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
                          "Listening...",
                          style: TextStyle(
                            color: MyAppTheme.mainFontColor,
                            fontSize: 14,
                            fontFamily: 'Cera Pro',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  if (speechToText.isListening) SizedBox(height: 8),
                  Text(
                    lastWords.isEmpty
                        ? "Hello! I am ARYA, your personal AI assistant. How can I help you today?"
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
                  if (isLoading && !speechToText.isListening)
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
