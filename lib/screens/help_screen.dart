import 'package:arya/theme/app_theme.dart';
import 'package:flutter/material.dart';

// Shared text styles for the built-in help pages.
const _headingStyle = TextStyle(
  color: MyAppTheme.mainFontColor,
  fontSize: 18,
  fontWeight: FontWeight.bold,
  fontFamily: 'Cera Pro',
);

const _bodyStyle = TextStyle(
  color: Colors.white,
  fontSize: 15,
  fontFamily: 'Cera Pro',
  height: 1.4,
);

const _bulletStyle = TextStyle(
  color: Colors.white70,
  fontSize: 15,
  fontFamily: 'Cera Pro',
  height: 1.4,
);

const _linkStyle = TextStyle(
  color: MyAppTheme.mainFontColor,
  fontSize: 16,
  fontWeight: FontWeight.bold,
  fontFamily: 'Cera Pro',
);

// Helpers written for screen readers: each element is its own text block
// and section titles are marked as headers.
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

/// Built-in usage guide.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

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
            _bullet('Say "new conversation" by voice for the same effect '
                'as the new-conversation button - ARYA saves the chat, '
                'stops talking, and starts a fresh one'),
            _bullet('The new-conversation button interrupts any speech at '
                'once, even mid-sentence, and starts a fresh chat - the '
                'conversation text is still saved to your selected folder '
                'first, so nothing is lost'),
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

            _heading('More topics'),
            Semantics(
              button: true,
              excludeSemantics: true,
              label: 'ARYA Model Routing. Double tap to open a detailed '
                  'guide to how ARYA chooses which model answers each '
                  'question.',
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const RoutingHelpScreen()),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('ARYA Model Routing', style: _linkStyle),
                      ),
                      const Icon(Icons.chevron_right,
                          color: MyAppTheme.mainFontColor),
                    ],
                  ),
                ),
              ),
            ),

            _heading('Works best with RemoteFix'),
            _body('ARYA is designed to work alongside RemoteFix, another '
                'app by the same developer. RemoteFix lets your standard '
                'Bluetooth headset buttons - play, pause, next, and '
                'previous - control Android notifications that do not '
                'normally respond to them.'),
            _body('ARYA shows a notification with controls for the '
                'microphone, a new conversation, Brave Search, and '
                'switching providers. With RemoteFix installed, your '
                'headset buttons can drive those controls, so you can '
                'run ARYA hands-free without touching the phone.'),
            _body('RemoteFix repository: github.com/dcon4/RemoteFix'),

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

/// Detailed guide on how ARYA picks the provider and model for each
/// question. Content mirrors the model routing report.
class RoutingHelpScreen extends StatelessWidget {
  const RoutingHelpScreen({super.key});

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
          "ARYA Model Routing",
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
            Semantics(
              header: true,
              child: const Padding(
                padding: EdgeInsets.only(top: 12, bottom: 8),
                child: Text(
                  'ARYA MODEL ROUTING - HOW THE SETTINGS BEHAVE',
                  style: _headingStyle,
                ),
              ),
            ),

            _heading('What routing means'),
            _body('Every time a question reaches the AI, ARYA picks two '
                'things: which company or service answers (the provider, '
                'like OpenRouter or Groq), and which brain it uses (the '
                'model). The choice is written to the debug log as a line '
                'starting with "Route:", so you can always see afterwards '
                'which provider and model actually answered.'),
            _body('Routing settings live in two places in Settings: the '
                'Model section for your main provider and model choice, '
                'and the Model Routing section for the auto-route switch '
                'and its four category rows. The Smart Confirmation '
                'switch nearby is about checking the question before '
                'answering, not about picking a model.'),

            _heading('The main choice: provider and model'),
            _body('Your main Model section choice is the foundation. It '
                'is used for every question when auto-route is off (the '
                'default), and as the fallback for every question when '
                'auto-route is on.'),
            _bullet('Each provider has a built-in default model if you '
                'never choose one.'),
            _bullet('The model list is fetched live from the provider '
                'when your API key is saved, so it stays current.'),
            _bullet('"Free Models Only" filters the list you pick from; '
                'it does not change routing by itself.'),
            _bullet('Safety net: if the provider rejects a model because '
                'it was renamed or removed, ARYA switches to a working '
                'one, saves it, and carries on. If the dead model was '
                'free, ARYA prefers another free model, and only if none '
                'is left falls back to a paid one - telling you in the '
                'spoken answer that the new model uses paid credits. '
                'Category rows pointing at the dead model are repaired '
                'automatically too.'),

            _heading('Auto-route'),
            _body('Auto-route sorts every question into one of four '
                'categories, checking in this fixed order: first Coding, '
                'then Quick, then Creative, and anything left over '
                'becomes Reasoning.'),
            _bullet('Coding: code, function, bug, python, api, compile, '
                'and similar programming words'),
            _bullet('Quick: what is, who is, when, where, how many, '
                'define, weather, time, temperature, capital, meaning, '
                'and similar short factual words'),
            _bullet('Creative: write, story, poem, describe, create, '
                'imagine, tell me about, essay, letter, email, and '
                'similar'),
            _bullet('Reasoning: the catch-all - why, explain, compare, '
                'analyze, and anything that matched none of the above'),
            _body('Because Coding is checked first, a mixed question '
                'goes to the earliest match: "write a python function" '
                'is Coding, not Creative.'),
            _body('The four category rows are live buttons. Tap a row, '
                'choose a provider (providers with no saved API key are '
                'marked so you do not pick a locked door), then choose a '
                'model. The row shows your pick, and the screen reader '
                'announces it. "Use my default model" resets the row to '
                'your main Model section choice.'),
            _body('With Auto-route on and a category configured, the log '
                '"Route:" line shows that category provider and model, '
                'so you can verify a routing choice by asking a matching '
                'question and reading the log. Weather, memory, and '
                'explicit web searches never reach routing - they are '
                'handled earlier by design.'),

            _heading('Smart Confirmation'),
            _body('Smart Confirmation does not pick a model. Research '
                'questions get a balanced answer presenting the accepted '
                'view and minority views, and complex or low-confidence '
                'questions trigger a spoken confirmation first so you can '
                'confirm or redirect instead of waiting for a long wrong '
                'answer. It is independent of Auto-route; both can be '
                'on.'),
            _bullet('Settings has a Research section with two editable '
                'boxes: what ARYA says to you when a research question is '
                'recognised, and the exact instructions sent to the AI to '
                'keep the answer balanced. Clear a box to return to the '
                'default text, and tap Save to apply'),

            _heading('Web search options'),
            _bullet('Brave Search: web results injected into the AI '
                'context when enabled with a key'),
            _bullet('Research questions only: when on, Brave is only '
                'called for research-type questions such as news or '
                'studies; everything else goes straight to your model'),
            _bullet('Web search on every request: appends OpenRouter\'s '
                ':online suffix, which costs extra credits even on free '
                'models'),
            _bullet('If Brave is on, the :online suffix is skipped - the '
                'two are alternatives, not stacked'),

            _heading('Quick reference'),
            _bullet('Provider and Model: the brain that answers, also the '
                'fallback'),
            _bullet('Free Models Only: filters the model list you pick '
                'from'),
            _bullet('Auto-route: sorts questions into four categories'),
            _bullet('Four category rows: tap to pick the provider and '
                'model per category'),
            _bullet('Smart Confirmation: confirmation and balanced '
                'research answers'),
            _bullet('Brave Search: web results for research questions'),
            _bullet('Web search on every request: OpenRouter :online '
                'suffix, extra credits'),

            _heading('If something seems wrong'),
            _bullet('Check the log "Route:" line - it always shows the '
                'provider and model that actually answered'),
            _bullet('If a model was replaced behind your back, the log '
                'says "Saved recovered model ..." or "Repaired routing '
                'model ..."'),
            _bullet('If you heard a note about a retired free model and '
                'paid credits, ARYA is telling you it had to leave the '
                'free tier'),
          ],
        ),
      ),
    );
  }
}
