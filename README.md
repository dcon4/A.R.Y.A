# A.R.Y.A - Adaptive Real-time Yielding Assistant

A voice-first AI assistant for Android, built with Flutter. Tap the mic (or
say the wake word), ask anything, and ARYA answers out loud: general
questions, weather, web search with articles read to you, and facts she
remembers about you.

This repository is a fork of
[4bhisheksharma/A.R.Y.A](https://github.com/4bhisheksharma/A.R.Y.A),
extended with hands-free reading, multi-provider model routing, memory,
wake word detection, and accessibility features for screen-reader users.

## Credits

The original A.R.Y.A project was created by **Abhishek Sharma**.

- Repository: [github.com/4bhisheksharma/A.R.Y.A](https://github.com/4bhisheksharma/A.R.Y.A)
- Website: [abhishek-sharma.com.np](https://abhishek-sharma.com.np)
- GitHub: [@4bhisheksharma](https://github.com/4bhisheksharma)
- LinkedIn: [Abhishek Sharma](https://linkedin.com/in/4bhisheksharma)

(c) 2025 Abhishek Sharma. All rights reserved. This fork builds on his
work with gratitude - without the original project, none of this would
exist.

## Screenshots and demo

<img src="assets/screenshots/Arya_home.jpeg" alt="Home screen" width="250"/>

[Watch the demo video](https://github.com/user-attachments/assets/14619f78-68c2-48f1-8b42-e3cfe967fd81)

## Features

- Voice conversation: ask questions by voice and hear spoken answers,
  with barge-in (talking over ARYA stops her current speech).
- Wake word: say "hey rhasspy" to open the mic without touching the
  phone (on-device detection, runs offline).
- Multiple AI providers: OpenRouter, OpenAI, Groq, DeepSeek, Cerebras,
  or a custom OpenAI-compatible endpoint. Model lists are fetched live
  from each provider; a "Free Models Only" filter helps you stay on
  free tiers.
- Auto-route: questions are sorted into Coding, Quick, Creative, or
  Reasoning, and each category can use its own provider and model. If a
  model ever disappears, ARYA swaps in a working one - preferring free
  replacements - and tells you when it had to fall back to a paid model.
- Smart Confirmation: complex or research-style questions get a spoken
  confirmation first, and research answers present opposing views, not
  just the mainstream one.
- Weather: set your US ZIP code in Settings and ask for the weather or
  forecast.
- Web search and article reading: say "search for ..." and ARYA reads
  the result titles. Say a number to open a result, "read all" to hear
  each article in turn, "more results" for the next batch, "repeat" to
  start the current article over, "next" or "skip" while reading, and
  "cancel" to exit.
- Optional web grounding: Brave Search results injected into the
  prompt (with a "Research questions only" mode), or OpenRouter's
  ":online" suffix for web search on every request.
- Memory: "remember I have two cats", "what do you remember",
  "forget cats", "clear my memories".
- Conversations are saved automatically as text files to your selected
  folder and can be shared from the app.
- Debug log sharing: a bug-report icon in the top bar sends the current
  log file to anyone, so problems can be diagnosed without a cable.

## Companion app: RemoteFix

ARYA works best with
[RemoteFix](https://github.com/dcon4/RemoteFix), another app by the same
developer. ARYA shows a notification with controls for the microphone,
a new conversation, Brave Search, and switching providers. RemoteFix
lets your standard Bluetooth headset buttons (play, pause, next,
previous) drive those notification controls, so ARYA can be run
hands-free without touching the phone.

## Installing

### Prebuilt APK (recommended)

1. Open the repository on GitHub and go to the **Actions** tab.
2. Open the most recent successful run of the "Build debug APK"
   workflow.
3. Download the `debug-apk` artifact at the bottom of the page.
4. Unzip it and install the APK on your Android phone (you may need to
   allow installs from your browser).

Debug builds are signed with a key stored in this repository, so
updates install over existing versions without uninstalling.

### Build from source

Prerequisites: Flutter SDK 3.8.1 or newer, and an Android toolchain.

```bash
git clone https://github.com/dcon4/A.R.Y.A.git
cd A.R.Y.A
flutter pub get
flutter run
```

## Getting started (first run)

1. Open Settings (gear icon).
2. **Model**: choose a provider, paste its API key (keys are created on
   the provider's website, for example openrouter.ai), then pick a
   model. Turn on "Free Models Only" if you want to avoid paid usage.
3. **Weather Settings**: enter your US ZIP code if you want weather
   answers.
4. Optional: **Brave Search** - paste a free API key from
   api.search.brave.com, and consider switching on "Research questions
   only" so web searches only happen for news/study-style questions.
5. Optional: **Wake Word Detection** - say "hey rhasspy" to start the
   hands-free mic.

## How to use it

- Tap the mic button and speak, or say "hey rhasspy" if wake word
  detection is on.
- Ask anything: "what's the capital of Australia", "write me a haiku
  about rain", "explain how tide tables work".
- Weather: "what's the weather" or "forecast".
- Web search: "search for solar powered trailers" - ARYA reads the
  result titles, then you can say a number to open one, "read all" to
  hear every article in sequence, "more results", "repeat", "new
  search", or "cancel".
- While an article is being read: "next", "skip", "repeat", or
  "cancel". Starting to talk yourself interrupts her immediately.
- New conversation: the new-conversation button (or its background
  control) interrupts TTS speech instantly, even mid-sentence - the
  conversation text is still saved to your selected folder first, so
  nothing is lost.
- Replay the last answer with the speaker icon on the response card.

## Settings quick reference

| Setting | What it does |
| --- | --- |
| System prompt | ARYA's personality and instructions |
| Model | Provider, API key, and default model |
| Model Routing | Auto-route switch plus per-category provider/model pickers |
| Smart Confirmation | Confirm complex questions; balanced research answers |
| Weather Settings | Your US ZIP code for forecasts |
| Web search toggle | Appends OpenRouter's `:online` suffix (extra credits) |
| Text to Speech | Voice, speed, and related playback options |
| Brave Search | Web results injected into the prompt; optional research-only mode |
| Memory | How ARYA stores and recalls facts you tell her |
| Wake Word | "hey rhasspy" hands-free mic |
| Background Service | Notification/widget controls (mic, new conversation, Brave, provider) |
| Settings Backup | Export and import your settings |

## Model routing in detail

The same guide is available inside the app: open Help, then tap
"ARYA Model Routing".

### What routing means

Every time a question reaches the AI (instead of weather, web search,
or memory commands), ARYA picks two things: which company or service
answers (the provider, like OpenRouter or Groq), and which brain it
uses (the model). The choice appears in the debug log as a line
starting with "Route:", so you can always see which provider and model
actually answered.

Routing lives in two places in Settings: the Model section (your main
provider and model) and the Model Routing section (the auto-route
switch and its four category rows). Smart Confirmation is about
checking the question before answering, not about picking a model.

### The main choice: provider and model

Used for every question when auto-route is off (the default), and as
the fallback for every question when auto-route is on.

- Each provider has a built-in default model if you never choose one.
- The model list is fetched live from the provider when your API key is
  saved, so it stays current.
- "Free Models Only" filters the list you pick from; it does not change
  routing by itself.
- Safety net: if the provider rejects a model (renamed or removed),
  ARYA switches to a working one, saves it, and carries on. If the dead
  model was free, ARYA prefers another free model, and only if none is
  left falls back to a paid one - telling you in the spoken answer that
  the new model uses paid credits. Category rows pointing at the dead
  model are repaired automatically too.

### Auto-route

Auto-route sorts every question into one of four categories, checking
in this fixed order: first Coding, then Quick, then Creative, and
anything left over becomes Reasoning.

- Coding: code, function, bug, python, api, compile, and similar
  programming words.
- Quick: what is, who is, when, where, how many, define, weather, time,
  temperature, capital, meaning, and similar short factual words.
- Creative: write, story, poem, describe, create, imagine, tell me
  about, essay, letter, email, and similar.
- Reasoning: the catch-all - why, explain, compare, analyze, and
  anything that matched none of the above.

Because Coding is checked first, a mixed question goes to the earliest
match: "write a python function" is Coding, not Creative.

The four category rows are live buttons. Tap a row, choose a provider
(providers with no saved API key are marked so you do not pick a
locked door), then choose a model. The row shows your pick and the
screen reader announces it. "Use my default model" resets the row to
your main Model section choice.

With Auto-route on and a category configured, the log "Route:" line
shows that category's provider and model. Weather, memory, and
explicit web searches never reach routing - they are handled earlier
by design.

### Smart Confirmation

Smart Confirmation does not pick a model. Research questions get a
balanced answer presenting the accepted view and minority views, and
complex or low-confidence questions trigger a spoken confirmation
first. It is independent of Auto-route; both can be on.

### Web search options

- Brave Search: web results injected into the AI context when enabled
  with a key.
- Research questions only: when on, Brave is only called for
  research-type questions such as news or studies; everything else goes
  straight to your model.
- Web search on every request: appends OpenRouter's `:online` suffix,
  which costs extra credits even on free models.
- If Brave is on, the `:online` suffix is skipped - the two are
  alternatives, not stacked.

### If something seems wrong

- Check the log's "Route:" line - it always shows the provider and
  model that actually answered.
- If a model was replaced behind your back, the log says "Saved
  recovered model ..." or "Repaired routing model ...".
- If you heard a note about a retired free model and paid credits,
  ARYA is telling you it had to leave the free tier.

## Reporting problems

Tap the bug-report icon in the top app bar and choose how to send the
log file (email, messaging, drive). The log is written with verbose
detail by default and survives crashes, so it is almost always enough
to find out what went wrong.

## License

This project is not open source, however you can use it by informing
the original author. See the Credits section above.

(c) 2025 Abhishek Sharma. All rights reserved.
