import 'dart:convert';
import 'package:arya/models/memory_entry.dart';
import 'package:arya/services/api_providers.dart' as providers;
import 'package:arya/services/brave_search_service.dart';
import 'package:arya/services/debug_logger.dart';
import 'package:arya/services/memory_service.dart';
import 'package:arya/services/query_classifier.dart';
import 'package:arya/services/searxng_search_service.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

String? _cachedApiKey;
String? _cachedModel;
String? _cachedBaseUrl;
bool? _cachedRequiresReferer;

Future<String> getApiKey() async {
  if (_cachedApiKey != null) return _cachedApiKey!;
  final key = await providers.getApiKey();
  if (key.isNotEmpty) {
    _cachedApiKey = key;
  }
  return key;
}

Future<String> getModel() async {
  if (_cachedModel != null) return _cachedModel!;
  final model = await providers.getSelectedModel();
  if (model.isNotEmpty) {
    _cachedModel = model;
  }
  return model;
}

Future<String> getBaseUrlCached() async {
  if (_cachedBaseUrl != null) return _cachedBaseUrl!;
  final url = await providers.getBaseUrl();
  if (url.isNotEmpty) {
    _cachedBaseUrl = url;
  }
  return url;
}

Future<bool> getRequiresRefererCached() async {
  if (_cachedRequiresReferer != null) return _cachedRequiresReferer!;
  final val = await providers.getRequiresReferer();
  _cachedRequiresReferer = val;
  return val;
}

String getSiteUrl() {
  return 'https://github.com/4bhisheksharma/A.R.Y.A';
}

String getSiteName() {
  return 'A.R.Y.A';
}

void clearCachedSettings() {
  _cachedApiKey = null;
  _cachedModel = null;
  _cachedBaseUrl = null;
  _cachedRequiresReferer = null;
}

Future<bool> hasValidApiKey() async {
  final key = await getApiKey();
  return key.isNotEmpty;
}

class OpenaiService {
  static const String defaultSystemPrompt = '''
You are ARYA (Adaptive Real-time Yielding Assistant), a helpful and friendly AI voice assistant.

Your characteristics:
- You are ARYA, NOT ChatGPT or any other AI
- Your full form name is Adaptive Real-time Yielding Assistant
- You are intelligent, helpful, and conversational
- You respond in a natural, friendly tone
- You keep responses concise and to the point (2-3 sentences max unless more detail is requested)
- You are designed to assist users with their questions and tasks
- You have a warm personality and care about helping users
- You are developed by Abhishek Sharma a Flutter developer (www.abhishek-sharma.com.np)
- You can provide information, answer questions, and engage in casual conversation
- You always refer to yourself as ARYA


When responding:
- Always be helpful and informative
- Use simple, clear language
- Be concise but thorough
- Show personality while remaining professional
- If you don't know something, admit it honestly

Remember: You are ARYA, the user's personal AI assistant.
''';

  /// Extra instructions appended to the system prompt for research
  /// questions so the model presents a balanced answer. Shown in
  /// Settings; the "research_prompt_extension" preference overrides it.
  static const String defaultResearchPrompt = '''ADDITIONAL INSTRUCTIONS FOR RESEARCH QUESTIONS:
When the user asks a research question, you must present a balanced view:
1. First state the accepted/mainstream view with its key evidence.
2. Then present the minority, dissenting, or alternative view with its key evidence.
3. Clearly label which is which (e.g. "The mainstream view is..." vs "A dissenting perspective argues...").
4. Do NOT uncritically accept the status quo. Actively look for and present credible minority or contrarian viewpoints.
5. If the evidence is genuinely one-sided, say so honestly rather than manufacturing a false balance.
6. End with a brief summary of where the debate stands and what remains uncertain.
''';

  static Future<String> getSystemPrompt({bool isResearch = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final base = prefs.getString('system_prompt') ?? defaultSystemPrompt;
    if (isResearch) {
      final custom = (prefs.getString('research_prompt_extension') ?? '').trim();
      if (custom.isNotEmpty) {
        return '$base\n\n$custom';
      }
      return '$base\n\n$defaultResearchPrompt';
    }
    return base;
  }

  static Future<void> setSystemPrompt(String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('system_prompt', prompt);
  }

  final _logger = DebugLogger();

  /// What actually served the last request. May differ from the planned
  /// route when a rate-limit fallback or a model recovery kicked in.
  String lastServedProviderId = '';
  String lastServedModel = '';

  Future<String?> chatGPTAPI(
    String prompt, {
    List<Map<String, String>>? history,
    String? providerId,
    String? overrideModel,
    List<MemoryEntry>? memories,
    int? maxTokens,
    bool isResearch = false,
  }) async {
    try {
      // Resolve provider: use override or default
      String resolvedProviderId = providerId ?? await providers.getSelectedProviderId();
      String resolvedApiKey;
      String resolvedBaseUrl;
      bool resolvedRequiresReferer;

      if (providerId != null) {
        resolvedApiKey = await providers.getApiKeyForProvider(providerId);
        resolvedBaseUrl = await providers.getBaseUrlForProvider(providerId);
        resolvedRequiresReferer = providers.getRequiresRefererForProvider(providerId);
      } else {
        resolvedApiKey = await getApiKey();
        resolvedBaseUrl = await getBaseUrlCached();
        resolvedRequiresReferer = await getRequiresRefererCached();
      }

      if (resolvedApiKey.isEmpty) {
        // Kilo's gateway serves its free tier without a key, so an empty
        // key there means "use the anonymous free tier" instead of a block.
        if (resolvedProviderId == 'kilo_code') {
          resolvedApiKey = 'anonymous';
          _logger.log('OpenAIService', 'Kilo Code: no key set — using the anonymous free tier');
        } else {
          _logger.log('OpenAIService', 'API call blocked - no API key set');
          return 'Please add your API key in Settings first.';
        }
      }

      var model = overrideModel ?? await getModel();
      if (resolvedBaseUrl.isEmpty) {
        _logger.log('OpenAIService', 'API call blocked - no base URL set');
        return 'Please set a base URL for your custom provider in Settings.';
      }

      final braveSearch = await BraveSearchService.isEnabled();
      final braveKey = await BraveSearchService.getApiKey();
      final braveResearchOnly = await BraveSearchService.isResearchOnly();
      final braveActive = braveSearch && braveKey.isNotEmpty;

      List<BraveSearchResult>? searchResults;
      if (braveActive) {
        var runBrave = true;
        if (braveResearchOnly) {
          final probe =
              await QueryClassifier.instance.classify(prompt, smartFreeEnabled: true);
          runBrave = probe.isResearch;
        }
        if (runBrave) {
          _logger.log('OpenAIService', 'Running Brave Search for: $prompt');
          final brave = BraveSearchService();
          searchResults = await brave.search(prompt);
          if (searchResults.isNotEmpty) {
            _logger.log('OpenAIService', 'Got ${searchResults.length} search results');
          }
        } else {
          _logger.log('OpenAIService', 'Brave skipped — research-only mode, not a research question');
        }
      }

      // SearXNG is the optional second grounding source: it fills in
      // when Brave is off or found nothing. Same research-only rule.
      final searxngActive = await SearxngSearchService.isEnabled();
      if ((searchResults == null || searchResults.isEmpty) && searxngActive) {
        var runSearxng = true;
        if (await SearxngSearchService.isResearchOnly()) {
          final probe =
              await QueryClassifier.instance.classify(prompt, smartFreeEnabled: true);
          runSearxng = probe.isResearch;
        }
        if (runSearxng) {
          _logger.log('OpenAIService', 'Running SearXNG search for: $prompt');
          final hits = await SearxngSearchService.instance.search(prompt, count: 5);
          searchResults = hits
              .map((r) =>
                  BraveSearchResult(title: r.title, url: r.url, snippet: r.snippet))
              .toList();
          if (searchResults.isNotEmpty) {
            _logger.log(
                'OpenAIService', 'Got ${searchResults.length} SearXNG results');
          }
        } else {
          _logger.log('OpenAIService',
              'SearXNG skipped — research-only mode, not a research question');
        }
      }

      final webSearch = !braveActive &&
          !searxngActive &&
          await providers.getWebSearchOnlineEnabled();
      if (webSearch && providers.providerSupportsWebSearch(resolvedProviderId) && !model.contains(':online')) {
        model = '$model:online';
      }

      lastServedProviderId = resolvedProviderId;
      lastServedModel = model;

      _logger.log('OpenAIService', 'Sending request to $resolvedBaseUrl model=$model');

      final sysPrompt = await getSystemPrompt(isResearch: isResearch);
      final messages = <Map<String, String>>[
        {'role': 'system', 'content': sysPrompt},
      ];
      // Inject relevant memories
      if (memories != null && memories.isNotEmpty) {
        final memoryText = MemoryService.instance.formatForPrompt(memories);
        if (memoryText.isNotEmpty) {
          messages.add({'role': 'system', 'content': memoryText});
        }
      }
      if (history != null) {
        messages.addAll(history);
      }
      if (searchResults != null && searchResults.isNotEmpty) {
        final context = BraveSearchService().formatResults(searchResults);
        messages.add({'role': 'system', 'content': context});
      }
      messages.add({'role': 'user', 'content': prompt});

      http.Response response;
      try {
        response = await _postChat(
          baseUrl: resolvedBaseUrl,
          apiKey: resolvedApiKey,
          requiresReferer: resolvedRequiresReferer,
          model: model,
          messages: messages,
          maxTokens: maxTokens,
        );
      } catch (e) {
        // The phone could not reach this provider at all (DNS, wifi,
        // server down). Another provider with a key may still answer.
        _logger.log('OpenAIService',
            'First attempt failed (${e.runtimeType}) — trying fallback providers');
        final fallback = await _tryFallbackProviders(
          resolvedProviderId,
          model,
          messages,
          maxTokens,
          webSearch,
        );
        if (fallback != null) return fallback;
        rethrow;
      }

      if (response.statusCode == 200) {
        _logger.log('OpenAIService', 'API response OK (${response.body.length} chars)');
        var content = _extractContent(response.body);
        if ((content == null || content.isEmpty) && maxTokens != null) {
          // Reasoning models can spend the whole max_tokens budget thinking
          // and return no answer. Retry once with no cap.
          _logger.log('OpenAIService', 'Empty content with max_tokens=$maxTokens — retrying without cap');
          final uncapped = await _postChat(
            baseUrl: resolvedBaseUrl,
            apiKey: resolvedApiKey,
            requiresReferer: resolvedRequiresReferer,
            model: model,
            messages: messages,
          );
          if (uncapped.statusCode == 200) {
            content = _extractContent(uncapped.body);
          } else {
            response = uncapped;
          }
        }
        if (content != null && content.isNotEmpty) return content;
        if (response.statusCode == 200) {
          _logger.error('OpenAIService', 'Model returned empty content: ${_debugChoices(response.body)}');
          return 'The model returned an empty answer. Please ask again, or pick a different model in Settings.';
        }
      }

      // Model no longer exists on this provider — discover a live one and retry once.
      if (_isModelMissing(response.statusCode, response.body)) {
        final recovery = await _recoverModel(resolvedProviderId, model);
        if (recovery != null && recovery.model != model) {
          _logger.log('OpenAIService', 'Retrying with recovered model: ${recovery.model} (paid fallback: ${recovery.paidFallback})');
          final retry = await _postChat(
            baseUrl: resolvedBaseUrl,
            apiKey: resolvedApiKey,
            requiresReferer: resolvedRequiresReferer,
            model: recovery.model,
            messages: messages,
            maxTokens: maxTokens,
          );
          if (retry.statusCode == 200) {
            _logger.log('OpenAIService', 'API response OK after model recovery (${retry.body.length} chars)');
            lastServedModel = recovery.model;
            var content = _extractContent(retry.body);
            if (content == null || content.isEmpty) {
              _logger.error('OpenAIService', 'Recovered model returned empty content: ${_debugChoices(retry.body)}');
              return 'The model returned an empty answer. Please ask again, or pick a different model in Settings.';
            }
            if (recovery.paidFallback) {
              content = '$content\n\nNote: the free model you were using was retired by the provider. ARYA switched to ${recovery.model}, which uses paid credits. You can pick another free model in Settings.';
            }
            return content;
          }
          response = retry;
        }
      }

      // Rate limited (429) — try other providers with keys
      if (response.statusCode == 429) {
        _logger.log('OpenAIService', 'Rate limited (429) on $resolvedProviderId, trying fallback providers...');
        final fallback = await _tryFallbackProviders(
          resolvedProviderId,
          model,
          messages,
          maxTokens,
          webSearch,
        );
        if (fallback != null) {
          _logger.log('OpenAIService', 'Fallback provider succeeded');
          return fallback;
        }
      }

      {
        _logger.error('OpenAIService', 'API error HTTP ${response.statusCode}');
        _logger.verbose('OpenAIService', 'Response body: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}');
        String detail;
        try {
          final err = jsonDecode(response.body);
          detail = err['error']['message'] ?? 'HTTP ${response.statusCode}';
        } catch (_) {
          detail = 'HTTP ${response.statusCode}';
        }
        if (_isModelMissing(response.statusCode, response.body)) {
          return 'I could not find an available AI model. Please open Settings and pick a model.';
        }
        return 'API error: $detail';
      }
    } catch (e) {
      _logger.error('OpenAIService', 'Request exception', e);
      return 'Sorry, something went wrong. Please check your connection.';
    }
  }

  /// Pull the assistant text out of a chat-completions body.
  /// Returns null when there is no usable text (empty, null, or whitespace).
  String? _extractContent(String body) {
    try {
      final data = jsonDecode(body);
      final content = data['choices']?[0]?['message']?['content'];
      String? text;
      if (content is String) {
        text = content;
      } else if (content is List) {
        // Some models return content as a list of typed parts.
        text = content
            .map((p) => p is Map ? (p['text'] ?? '').toString() : p.toString())
            .join();
      }
      if (text == null || text.trim().isEmpty) return null;
      return text;
    } catch (_) {
      return null;
    }
  }

  /// Compact diagnostics for an empty-content response.
  String _debugChoices(String body) {
    try {
      final data = jsonDecode(body);
      final choice = data['choices']?[0];
      final msg = choice is Map ? choice['message'] : null;
      final keys = msg is Map ? msg.keys.join(',') : 'n/a';
      final reasoning = msg is Map
          ? ((msg['reasoning'] ?? msg['reasoning_content'])?.toString().length ?? 0)
          : 0;
      return 'finish=${choice is Map ? choice['finish_reason'] : '?'} keys=$keys reasoningChars=$reasoning';
    } catch (_) {
      return 'unparseable body';
    }
  }

  bool _isModelMissing(int status, String body) {
    if (status != 400 && status != 404 && status != 422) return false;
    final lower = body.toLowerCase();
    return lower.contains('model_not_found') ||
        lower.contains('does not exist') ||
        lower.contains('not a valid model') ||
        lower.contains('invalid model') ||
        lower.contains('unknown model') ||
        lower.contains('no such model');
  }

  Future<http.Response> _postChat({
    required String baseUrl,
    required String apiKey,
    required bool requiresReferer,
    required String model,
    required List<Map<String, String>> messages,
    int? maxTokens,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    };
    if (requiresReferer) {
      headers['HTTP-Referer'] = getSiteUrl();
      headers['X-Title'] = getSiteName();
    }
    return http.post(
      Uri.parse('$baseUrl/chat/completions'),
      headers: headers,
      body: jsonEncode({
        'model': model,
        'messages': messages,
        if (maxTokens != null) 'max_tokens': maxTokens,
      }),
    ).timeout(const Duration(seconds: 60));
  }

  /// Find a live model for this provider, persist it, and return it.
  /// If the broken model was free, prefers a free replacement; reports
  /// [paidFallback] when it had to settle on a paid one.
  Future<_ModelRecovery?> _recoverModel(String providerId, String badModel) async {
    // The local model is only reachable through the computer's Research
    // Assistant (local search) - never as a general-chat provider.
    if (providerId == 'local') return null;
    try {
      final apiKey = await providers.getApiKeyForProvider(providerId);
      // Kilo's model list is public (anonymous tier), so an empty key is
      // fine there; every other provider needs a key to list models.
      if (apiKey.isEmpty && providerId != 'kilo_code') return null;

      List<Map<String, dynamic>> models = [];
      // Import kept local via ModelFetcher through a light dependency.
      final fetcher = _ModelFetcher();
      switch (providerId) {
        case 'openrouter':
          models = await fetcher.fetchOpenRouterModels(apiKey);
          break;
        case 'openai':
          models = await fetcher.fetchOpenAIModels(apiKey);
          break;
        case 'groq':
          models = await fetcher.fetchGroqModels(apiKey);
          break;
        case 'deepseek':
          models = await fetcher.fetchDeepSeekModels(apiKey);
          break;
        case 'cerebras':
          models = await fetcher.fetchCerebrasModels(apiKey);
          break;
        case 'kilo_code':
          models = await fetcher.fetchKiloCodeModels(
              apiKey.isEmpty ? 'anonymous' : apiKey);
          break;
      }

      final wasFree = _modelIsFree(providerId, badModel);

      if (models.isEmpty) {
        final provider = providers.apiProviders.firstWhere(
          (p) => p.id == providerId,
          orElse: () => providers.apiProviders.first,
        );
        if (provider.defaultModel.isNotEmpty && provider.defaultModel != badModel) {
          await _persistModel(providerId, provider.defaultModel, badModel);
          return _ModelRecovery(
            provider.defaultModel,
            wasFree && !_modelIsFree(providerId, provider.defaultModel),
          );
        }
        return null;
      }

      // Prefer non-guard / non-whisper chat models.
      const blocked = ['whisper', 'prompt-guard', 'safeguard', 'moderation', 'audio'];
      String? pickFrom(List<Map<String, dynamic>> list) {
        for (final m in list) {
          final id = (m['id'] ?? '').toString();
          final lower = id.toLowerCase();
          if (id.isEmpty || id == badModel) continue;
          if (blocked.any((b) => lower.contains(b))) continue;
          return id;
        }
        return null;
      }

      String? chosen;
      if (wasFree) {
        chosen = pickFrom(models.where((m) => m['is_free'] == true).toList());
        if (chosen == null) {
          _logger.log('OpenAIService', 'No free model left on $providerId — falling back to paid');
        }
      }
      chosen ??= pickFrom(models);
      chosen ??= (models.first['id'] ?? '').toString();
      if (chosen.isEmpty) return null;

      final info = models.where((m) => (m['id'] ?? '').toString() == chosen);
      final chosenIsFree = info.isNotEmpty
          ? info.first['is_free'] == true
          : _modelIsFree(providerId, chosen);

      await _persistModel(providerId, chosen, badModel);
      return _ModelRecovery(chosen, wasFree && !chosenIsFree);
    } catch (e) {
      _logger.error('OpenAIService', 'Model recovery failed', e);
      return null;
    }
  }

  /// Free-status per provider: OpenRouter free variants carry ":free",
  /// Groq's developer tier is free, the others bill per usage.
  bool _modelIsFree(String providerId, String modelId) {
    switch (providerId) {
      case 'openrouter':
        return modelId.contains(':free');
      case 'groq':
        return true;
      case 'kilo_code':
        return modelId.contains('free');
      default:
        return false;
    }
  }

  /// Providers that serve capable models without metered billing. Used to
  /// order fallback candidates free-first so a switch rarely spends credits.
  static const List<String> _freeTierProviderIds = [
    'groq',
    'cerebras',
    'nim',
    'zen',
    'kilo_code',
    'kiloworks_ai',
  ];

  /// Try other providers with API keys when rate limited (429).
  /// [webSearch] is the raw user intent — each candidate decides for itself
  /// whether it can honour it, because only some support the `:online` suffix.
  Future<String?> _tryFallbackProviders(
    String currentProviderId,
    String model,
    List<Map<String, String>> messages,
    int? maxTokens,
    bool webSearch,
  ) async {
    // Free-tier providers first (registry order preserved inside each group).
    // 'local' is excluded: its address only exists on the computer, so it can
    // never answer a phone-side chat request.
    final allProviders = providers.apiProviders
        .where((p) => p.id != currentProviderId && p.id != 'local');
    final candidates = [
      ...allProviders.where((p) => _freeTierProviderIds.contains(p.id)),
      ...allProviders.where((p) => !_freeTierProviderIds.contains(p.id)),
    ];

    // Cap the attempts: each try can take up to 60s and a voice user is
    // waiting. Three is enough to get past a single rate-limited provider.
    var attempts = 0;
    for (final p in candidates) {
      if (attempts >= 3) {
        _logger.log('OpenAIService', 'Fallback attempt cap (3) reached — giving up');
        break;
      }
      final apiKey = await providers.getApiKeyForProvider(p.id);
      // Kilo's gateway accepts the anonymous free tier when no key is set.
      final candidateKey = apiKey.isEmpty && p.id == 'kilo_code' ? 'anonymous' : apiKey;
      if (candidateKey.isEmpty) continue;
      if (p.id == 'custom') {
        final url = await providers.getBaseUrlForProvider('custom');
        if (url.isEmpty) continue;
      }

      _logger.log('OpenAIService', 'Trying fallback provider: ${p.id}');
      try {
        // Match against the bare model name — the original may carry a
        // ":online" suffix added by the web-search pass above.
        final bareModel = model.replaceFirst(RegExp(r':online$'), '');
        final fallbackModel = _pickFallbackModel(p, bareModel);

        // Honour the raw web-search intent per candidate.
        var finalModel = fallbackModel;
        if (webSearch && p.supportsWebSearch && !finalModel.contains(':online')) {
          finalModel = '$finalModel:online';
        }
        if (finalModel.isEmpty) {
          _logger.log('OpenAIService', 'Fallback ${p.id} has no model configured, skipping');
          continue;
        }

        final baseUrl = await providers.getBaseUrlForProvider(p.id);
        final requiresReferer = providers.getRequiresRefererForProvider(p.id);

        attempts++;
        final response = await _postChat(
          baseUrl: baseUrl,
          apiKey: candidateKey,
          requiresReferer: requiresReferer,
          model: finalModel,
          messages: messages,
          maxTokens: maxTokens,
        );

        if (response.statusCode == 200) {
          final content = _extractContent(response.body);
          if (content != null && content.isNotEmpty) {
            _logger.log('OpenAIService', 'Fallback to ${p.id} ($finalModel) succeeded');
            // Persist the working provider/model everywhere, including the
            // per-category routing pairs that still point at the blocked one.
            await _persistFallbackChoice(currentProviderId, model, p.id, finalModel);
            lastServedProviderId = p.id;
            lastServedModel = finalModel;
            var answer =
                '$content\n\nNote: ARYA switched to ${p.name} ($finalModel) because your primary provider was rate limited.';
            if (_isPaidChoice(p, finalModel)) {
              answer +=
                  ' Heads up: $finalModel uses paid credits. You can pick another model in Settings.';
            }
            return answer;
          }
          _logger.log('OpenAIService', 'Fallback ${p.id} returned empty content, trying next...');
        } else if (response.statusCode == 429) {
          _logger.log('OpenAIService', 'Fallback ${p.id} also rate limited, trying next...');
        } else {
          _logger.log('OpenAIService', 'Fallback ${p.id} HTTP ${response.statusCode}, trying next...');
        }
      } catch (e) {
        _logger.log('OpenAIService', 'Fallback ${p.id} error: $e');
      }
    }
    return null;
  }

  /// Pick the model a fallback candidate should use: the original model when
  /// the provider carries it, otherwise that provider's first free model,
  /// otherwise the provider default.
  String _pickFallbackModel(providers.ApiProvider p, String bareModel) {
    if (p.models.any((m) => m.id == bareModel)) return bareModel;
    for (final m in p.models) {
      final label = m.label.toLowerCase();
      if (m.id.contains(':free') || (label.contains('free') && !label.contains('paid'))) {
        return m.id;
      }
    }
    return p.defaultModel;
  }

  /// True when the chosen model bills paid credits. Free-tier providers and
  /// custom endpoints count as free (flat-rate or self-hosted).
  bool _isPaidChoice(providers.ApiProvider p, String modelId) {
    if (_freeTierProviderIds.contains(p.id) || p.id == 'custom') return false;
    final bare = modelId.replaceFirst(RegExp(r':online$'), '');
    final matches = p.models.where((m) => m.id == bare);
    if (matches.isNotEmpty) {
      final label = matches.first.label.toLowerCase();
      if (label.contains('paid')) return true;
      if (label.contains('free')) return false;
    }
    if (p.id == 'openrouter') return !modelId.contains(':free');
    if (p.id == 'openai' || p.id == 'deepseek') return true;
    return false;
  }

  /// Persist a successful fallback: the global provider/model plus every
  /// per-category routing pair that still points at the blocked provider,
  /// so smart routing does not keep hitting the same rate limit.
  Future<void> _persistFallbackChoice(
    String failedProviderId,
    String failedModel,
    String newProviderId,
    String newModel,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_provider', newProviderId);
    await prefs.setString('api_model', newModel);
    final bareNew = newModel.replaceFirst(RegExp(r':online$'), '');
    final newProvider = providers.apiProviders.firstWhere(
      (p) => p.id == newProviderId,
      orElse: () => providers.apiProviders.first,
    );
    for (final category in ['quick', 'reasoning', 'creative', 'coding']) {
      final rp = prefs.getString('routing_${category}_provider_id') ?? '';
      if (rp != failedProviderId) continue;
      final rm = prefs.getString('routing_${category}_model') ?? '';
      final bareRm = rm.replaceFirst(RegExp(r':online$'), '');
      // Keep the category's own model when the new provider carries it,
      // otherwise point it at the model that just worked.
      final keepModel = bareRm.isNotEmpty && newProvider.models.any((m) => m.id == bareRm);
      final targetModel = keepModel ? bareRm : bareNew;
      await prefs.setString('routing_${category}_provider_id', newProviderId);
      await prefs.setString('routing_${category}_model', targetModel);
      _logger.log('OpenAIService', 'Repaired $category routing -> $newProviderId / $targetModel');
    }
    clearCachedSettings();
    _logger.log('OpenAIService', 'Persisted fallback $newProviderId / $newModel (was $failedProviderId / $failedModel)');
  }

  Future<void> _persistModel(String providerId, String model, String badModel) async {
    final prefs = await SharedPreferences.getInstance();
    // Only overwrite the global model when this is the active provider,
    // or when the stored model is the broken one.
    final currentProvider = prefs.getString('api_provider') ?? 'openrouter';
    final currentModel = prefs.getString('api_model') ?? '';
    if (currentProvider == providerId || currentModel.isEmpty || _looksLikeBrokenPair(providerId, currentModel)) {
      await prefs.setString('api_model', model);
      await prefs.setString('api_provider', providerId);
    }
    // Repair any per-category routing pair that still points at the broken model.
    for (final category in ['quick', 'reasoning', 'creative', 'coding']) {
      final rp = prefs.getString('routing_${category}_provider_id') ?? '';
      final rm = prefs.getString('routing_${category}_model') ?? '';
      if (rp == providerId && rm == badModel) {
        await prefs.setString('routing_${category}_model', model);
        _logger.log('OpenAIService', 'Repaired $category routing model -> $model');
      }
    }
    clearCachedSettings();
    _logger.log('OpenAIService', 'Saved recovered model $model for $providerId');
  }

  bool _looksLikeBrokenPair(String providerId, String model) {
    if (providerId == 'openrouter' && !model.contains('/')) return true;
    if (providerId == 'groq' && model == 'llama-3.3-70b-versatile') return true;
    return false;
  }
}

/// Result of model recovery: the replacement model, plus whether a free
/// model had to be swapped for a paid one.
class _ModelRecovery {
  final String model;
  final bool paidFallback;
  const _ModelRecovery(this.model, this.paidFallback);
}

/// Thin wrapper so OpenaiService can recover models without a circular import graph issue.
class _ModelFetcher {
  Future<List<Map<String, dynamic>>> fetchOpenRouterModels(String key) =>
      _fetch('https://openrouter.ai/api/v1/models', key, (m) {
        if ((m['id'] ?? '').toString().contains(':free')) return true;
        final pricing = m['pricing'];
        if (pricing is Map && pricing['prompt'] != null) {
          return double.tryParse(pricing['prompt'].toString()) == 0.0;
        }
        return false;
      });
  Future<List<Map<String, dynamic>>> fetchOpenAIModels(String key) =>
      _fetch('https://api.openai.com/v1/models', key, (_) => false);
  Future<List<Map<String, dynamic>>> fetchGroqModels(String key) =>
      _fetch('https://api.groq.com/openai/v1/models', key, (_) => true);
  Future<List<Map<String, dynamic>>> fetchDeepSeekModels(String key) =>
      _fetch('https://api.deepseek.com/models', key, (_) => false);
  Future<List<Map<String, dynamic>>> fetchCerebrasModels(String key) =>
      _fetch('https://api.cerebras.ai/v1/models', key, (_) => false);
  Future<List<Map<String, dynamic>>> fetchKiloCodeModels(String key) =>
      _fetch('https://api.kilo.ai/api/gateway/models', key,
          (m) => (m['id'] ?? '').toString().toLowerCase().contains('free'));

  Future<List<Map<String, dynamic>>> _fetch(
    String url,
    String key,
    bool Function(dynamic raw) isFree,
  ) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $key'},
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body);
      final list = data['data'] as List? ?? [];
      return list
          .map((m) => {
                'id': m['id'] ?? '',
                'name': m['name'] ?? m['id'] ?? '',
                'is_free': isFree(m),
              })
          .where((m) => (m['id'] as String).isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }
}
