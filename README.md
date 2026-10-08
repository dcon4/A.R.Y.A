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
  NVIDIA NIM, OpenCode Zen, Kilo Code, Cloudflare Workers AI, Ollama
  Cloud (ollama.com), Venice.ai (venice.ai), or a custom
  OpenAI-compatible endpoint. Model
  lists are fetched live from each provider; a "Free Models Only"
  filter helps you stay on free tiers. If a provider is rate limited,
  ARYA automatically switches to another saved provider - free ones
  first - and says so.
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
  the result titles. Say or type a number to open a result, or two
  numbers like "2 5" to hear those two articles one after the other,
  "read all" to hear
  each article in turn, "more results" for the next batch, "repeat" to
  start the current article over, "next" or "skip" while reading, and
  "cancel" to exit. Results come from your own SearXNG server if you
  pick that source in Settings, then from Exa when its key is saved,
  and otherwise from DuckDuckGo. The
  full results list, with descriptions and links, also appears on
  screen, and every search and every article you read is saved into
  the conversation transcript, together with how long each answer took.
- Optional web grounding: SearXNG from your own computer as a keyless
  first choice, Exa Search when you add its key (it also supplies
  article text in voice web search), Brave Search (with a "Research
  questions only" mode) after that, or OpenRouter's
  ":online" suffix for web search on every request.
- Local search: ask questions about the documents on your own computer
  over your home wifi - say "local search" followed by your question,
  or "ask my documents". ARYA answers out loud and names where the
  answer was found. No password; only works at home. A second command,
  "private search", looks only in your private folder and is always
  answered by the model on the PC - the question and passages never
  leave the computer. The provider list
  includes "Local model (this computer)" so answers can come from a
  model running on the PC itself - private, nothing sent online,
  slower, and the computer must be on. If the computer seems
  unreachable although it is on, set A.R.Y.A's battery use to
  Unrestricted (Settings, Apps, A.R.Y.A, Battery) - battery saving can
  cut network connections.
- Memory: "remember I have two cats", "what do you remember",
  "forget cats", "clear my memories".
- Conversations are saved automatically as text files to your selected
  folder and can be shared from the app. Every saved reply records the
  provider, model, and routing category that produced it.
- Voice command: say "new conversation" to start a fresh chat - the
  same as the button, and the current chat is saved first.
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
5. Optional: **Exa Search** - paste an API key from
   dashboard.exa.ai/api-keys. Exa feeds web results into answers and
   also supplies the article text during voice web search.
6. Optional: **SearXNG** - run the free SearXNG program on your
   computer (with its JSON API enabled) and enter its address in
   Settings. ARYA then uses it for web grounding, and you can pick it
   as the voice-search source instead of DuckDuckGo. No key, no cost;
   SearXNG runs first, with Exa and Brave filling in.
7. Optional: **Wake Word Detection** - say "hey rhasspy" to start the
   hands-free mic.

## How to use it

- Tap the mic button and speak, or say "hey rhasspy" if wake word
  detection is on.
- Ask anything: "what's the capital of Australia", "write me a haiku
  about rain", "explain how tide tables work".
- Long answers - from a normal question or a local search - can be
  interrupted: say "hey rhasspy", tap the mic, or just start talking
  and ARYA stops mid-sentence so you can ask a follow-up. The reply
  is still saved in full, so nothing is lost when you start a new
  conversation.
- Weather: "what's the weather" or "forecast".
- Web search: "search for solar powered trailers" - ARYA reads the
  result titles, then you can say a number to open one, "read all" to
  hear every article in sequence, "more results", "repeat", "new
  search", or "cancel".
- While an article is being read: "next", "skip", "repeat", or
  "cancel". Starting to talk yourself interrupts her immediately.
- Local search: "local search where is my passport" or "ask my
  documents" - ARYA asks the Research Assistant on your computer and
  speaks the answer plus the source. Say just the command to be asked
  for your question. Typing the same words in the text box works the
  same way. Follow-ups work too: after a search, the next three
  questions automatically continue as local searches (say "new
  conversation" to stop sooner), and the last three turns are sent
  along so "what about his other books?" makes sense.
- New conversation: say "new conversation" by voice, or use the
  new-conversation button (or its background control) - it interrupts
  TTS speech instantly, even mid-sentence - the conversation text is
  still saved to your selected folder first, so nothing is lost.
- Replay the last answer with the speaker icon on the response card,
  or just say "replay" - same button, by voice.
- Typed shortcuts in the text box: "l s" starts a local search, "p s"
  a private search, "w s" a web search, and inside a web search "r a"
  reads all results - typing two numbers like "2 5" reads those two
  articles in order. You can add the question straight after the
  shortcut, for example "l s where is my passport".
- If a request fails (busy model or dropped connection), a Retry button
  appears under the answer - tap it to send the same request again.
- Second opinion: after an answer, say "second opinion" (or "another
  opinion"), or tap the Second opinion button under the answer. ARYA
  re-asks the same question - with the same injected search results -
  to a different model you choose in Settings, under Model Routing,
  and the new answer appears under the first one. Both answers stay
  in the same transcript. Until you pick a model, ARYA tells you
  where to set one.

## Settings quick reference

| Setting | What it does |
| --- | --- |
| System prompt | ARYA's personality and instructions |
| Model | Provider, API key, and default model |
| Model Routing | Auto-route switch, per-category pickers, and the second-opinion model |
| Smart Confirmation | Confirm complex questions; balanced research answers |
| Weather Settings | Your US ZIP code for forecasts |
| Web search toggle | Appends OpenRouter's `:online` suffix (extra credits) |
| Text to Speech | Voice, speed, and related playback options |
| Brave Search | Web results injected into the prompt; optional research-only mode |
| Exa Search | Web results injected into the prompt plus article text in voice search; optional research-only mode |
| SearXNG | Optional self-hosted search server for prompt grounding and the voice-search source |
| Local Search | On/off, your computer's address, and the provider/model to use |
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
starting with "Route:". When a different provider answers instead -
because the first one was busy - a "Served by" line shows what
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
- Rate limit: if a provider answers "too many requests", ARYA tries
  your other saved providers automatically - free ones first, up to
  three attempts - saves the one that worked (repairing any category
  rows that pointed at the busy provider), and adds a note naming the
  switch, with a paid-credits warning when it had to leave the free
  tier.

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

Below the four categories sits the Second opinion row, and it works
the same way: it picks the provider and model that re-answers your
last question when you say "second opinion" or tap the Second opinion
button. It is independent of Auto-route, so you can set it with
Auto-route off. Until you choose a model the row shows "Not set".

With Auto-route on and a category configured, the log "Route:" line
shows that category's provider and model. Weather, memory, and
explicit web searches never reach routing - they are handled earlier
by design.

### Smart Confirmation

Smart Confirmation does not pick a model. Research questions get a
balanced answer presenting the accepted view and minority views, and
complex or low-confidence questions trigger a spoken confirmation
first. It is independent of Auto-route; both can be on.
Settings has a Research section with two editable boxes: the
announcement spoken when a research question is recognised, and the
exact instructions appended to the system prompt for research so the
model stays balanced. Clear a box to restore its default text and tap
Save to apply.

### Web search options

- Brave Search: web results injected into the AI context when enabled
  with a key.
- Research questions only: when on, Brave (or Exa) is only called for
  research-type questions such as news or studies; everything else goes
  straight to your model.
- Exa Search: web results injected into the AI context when enabled
  with a key, and clean article text for voice web search when a page
  cannot be fetched normally. Get a key at dashboard.exa.ai/api-keys.
- SearXNG: optional, runs on your own computer. ARYA asks it for web
  results and feeds them to the AI, just like Brave or Exa - no key,
  no cost. SearXNG runs first; Exa and Brave fill in when SearXNG is
  off or finds nothing.
- Web search on every request: appends OpenRouter's `:online` suffix,
  which costs extra credits even on free models.
- If SearXNG, Exa, or Brave actually found results, the `:online`
  suffix is skipped - they are alternatives, not stacked. If a source
  was asked but found nothing, `:online` can step in.

### How search results reach the model

When a question goes to the AI, fresh web results can be looked up
first and handed to the model as part of the prompt:

- Your words are cleaned into a search query first: voice filler like
  "check the recent news" is stripped away, and a follow-up with too
  little left in it re-uses the topic from earlier in the conversation.
- Sources are tried in order and the first one that finds something
  wins: your own SearXNG server, then Exa Search, then Brave Search,
  then DuckDuckGo as a rescue when a configured source was asked but
  found nothing.
- Each of Brave, Exa and SearXNG has its own "Research questions only"
  switch; when it is on, a classifier checks the question first and
  everyday questions skip that source.
- The results become a numbered list of title, link and description,
  introduced by instructions: use these to answer, cite the sources,
  say honestly when they do not contain the answer, and trust them
  over the model's training data about recent events.
- That list sits directly above your current question in the prompt,
  after the personality rules, your saved memories and the
  conversation so far.
- If nothing was found, no list is added and the model answers from
  its own knowledge - which is why answers used to go stale when
  searches failed. The fallbacks above exist to make that rare.

This is separate from the spoken "web search" command: that path
never touches the model. ARYA fetches the pages herself - asking Exa
for the article text first when its key is saved, and downloading the
page otherwise - reads them to you, and saves them to the
conversation transcript.

### If something seems wrong

- Check the log's "Route:" line for the planned choice and the "Served
  by" line for what actually answered when they differ.
- If you heard "ARYA switched to ..." the main provider was rate
  limited and another saved provider answered instead.
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
