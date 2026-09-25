import 'package:arya/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Built-in usage guide. Everything here is written to be comfortable
/// with a screen reader: section titles are marked as headers, and each
/// line is its own text element so TalkBack reads it cleanly.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const _headingStyle = TextStyle(
    color: MyAppTheme.mainFontColor,
    fontSize: 18,
    fontWeight: FontWeight.bold,
    fontFamily: 'Cera Pro',
  );

  static const _bodyStyle = TextStyle(
    color: Colors.white,
    fontSize: 15,
    fontFamily: 'Cera Pro',
    height: 1.4,
  );

  static const _bulletStyle = TextStyle(
    color: Colors.white70,
    fontSize: 15,
    fontFamily: 'Cera Pro',
    height: 1.4,
  );

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 8),
        child: Semantics(
          header: true,
          child: Text(text, style: _headingStyle),
        ),
      );

  Widget _body(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: _bodyStyle),
      );

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text('- $text', style: _bulletStyle),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MyAppTheme.mainFontColor),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        title: const Text(
          "Help",
          style: TextStyle(
            color: MyAppTheme.mainFontColor,
            fontSize: 22,
            fontWeight: FontWeight.bold,
            fontFamily: 'Cera Pro',
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _heading('Getting started'),
            _body('Tap the microphone button and speak. If wake word '
                'detection is on in Settings, you can also just say '
                '"hey rhasspy" to open the mic without touching the phone.'),
            _body('Ask anything in plain language, for example:'),
            _bullet('"what is the capital of Australia"'),
            _bullet('"write me a haiku about rain"'),
            _bullet('"explain how tide tables work"'),
            _body('ARYA answers out loud. Start talking at any moment and '
                'she stops immediately so you can take over.'),

            _heading('Weather'),
            _body('Set your US ZIP code under Settings, Weather Settings. '
                'Then ask "what is the weather" or "forecast".'),

            _heading('Remembering facts'),
            _bullet('"remember I have two cats"'),
            _bullet('"remember that" to save your last statement'),
            _bullet('"what do you remember" to hear them back'),
            _bullet('"forget cats" to remove one'),
            _bullet('"clear my memories" to remove everything'),

            _heading('Web search and article reading'),
            _body('Say "search for ..." or "find ..." to start a web '
                'search. ARYA reads the result titles first.'),
            _bullet('Say a number, like "one", to open that result and '
                'hear the article'),
            _bullet('"read all" to hear every article in turn'),
            _bullet('"more results" for the next five results'),
            _bullet('"repeat" to start the current article again'),
            _bullet('"next" or "skip" while reading to move on'),
            _bullet('"new search" to start a different search'),
            _bullet('"cancel" to exit search mode'),
            _body('If ARYA is reading and you want her to stop, just start '
                'talking.'),

            _heading('Conversations'),
            _bullet('The new-conversation button stops any speech at once '
                'and starts fresh; the previous conversation is saved to '
                'a file first'),
            _bullet('The save button exports the current conversation so '
                'you can share it'),
            _bullet('The speaker icon on the last answer replays it'),

            _heading('Settings at a glance'),
            _bullet('Model: provider, API key, and default model'),
            _bullet('Model Routing: auto-route and a provider/model '
                'choice for coding, quick, creative, and reasoning '
                'questions'),
            _bullet('Smart Confirmation: confirm complex questions first '
                'and get balanced research answers'),
            _bullet('Weather Settings: your US ZIP code'),
            _bullet('Text to Speech: voice and speed'),
            _bullet('Brave Search: web results for research questions'),
            _bullet('Memory: what ARYA stores about you'),
            _bullet('Wake Word: hands-free "hey rhasspy"'),
            _bullet('Settings Backup: export and import everything'),

            _heading('If something goes wrong'),
            _body('Tap the bug-report icon in the top bar and choose how '
                'to send the log file, such as email or messaging. '
                'Detailed logging is on by default, so the log shows '
                'exactly what happened.'),

            _heading('About'),
            _body('A.R.Y.A - Adaptive Real-time Yielding Assistant. '
                'A voice assistant built with Flutter.'),
            _body('Original project by Abhishek Sharma: '
                'github.com/4bhisheksharma/A.R.Y.A. This app is an '
                'extended fork, built on that work with gratitude.'),
          ],
        ),
      ),
    );
  }
}
