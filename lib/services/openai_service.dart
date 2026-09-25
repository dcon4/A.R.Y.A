import 'dart:convert';
import 'package:arya/models/memory_entry.dart';
import 'package:arya/services/api_providers.dart' as providers;
import 'package:arya/services/brave_search_service.dart';
import 'package:arya/services/debug_logger.dart';
import 'package:arya/services/memory_service.dart';
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

  static const String _researchPromptExtension = '''

ADDITIONAL INSTRUCTIONS FOR RESEARCH QUESTIONS:
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
      return '$base$_researchPromptExtension';
    }
    return base;
  }

  static Future<void> setSystemPrompt(String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('system_prompt', prompt);
  }

  final _logger = DebugLogger();

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
        _logger.log('OpenAIService', 'API call blocked - no API key set');
        return 'Please add your API key in Settings first.';
      }

      var model = overrideModel ?? await getModel();
      if (resolvedBaseUrl.isEmpty) {
        _logger.log('OpenAIService', 'API call blocked - no base URL set');
        return 'Please set a base URL for your custom provider in Settings.';
      }

      final braveSearch = await BraveSearchService.isEnabled();
      final braveKey = await BraveSearchService.getApiKey();

      List<BraveSearchResult>? searchResults;
      if (braveSearch && braveKey.isNotEmpty) {
        _logger.log('OpenAIService', 'Running Brave Search for: $prompt');
        final brave = BraveSearchService();
        searchResults = await brave.search(prompt);
        if (searchResults.isNotEmpty) {
          _logger.log('OpenAIService', 'Got ${searchResults.length} search results');
        }
      }

      final webSearch = !braveSearch && await providers.getWebSearchOnlineEnabled();
      if (webSearch && resolvedProviderId == 'openrouter' && !model.contains(':online')) {
        model = '$model:online';
      }

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

      var response = await _postChat(
        baseUrl: resolvedBaseUrl,
        apiKey: resolvedApiKey,
        requiresReferer: resolvedRequiresReferer,
        model: model,
        messages: messages,
        maxTokens: maxTokens,
      );

      if (response.statusCode == 200) {
        _logger.log('OpenAIService', 'API response OK (${response.body.length} chars)');
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'];
        return content;
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
            final data = jsonDecode(retry.body);
            final content = data['choices'][0]['message']['content'];
            if (recovery.paidFallback) {
              return '$content\n\nNote: the free model you were using was retired by the provider. ARYA switched to ${recovery.model}, which uses paid credits. You can pick another free model in Settings.';
            }
            return content;
          }
          response = retry;
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

  bool _isModelMissing(int status, String body) {
    if (status != 400 && status != 404 && status != 422) return false;
    final lower = body.toLowerCase();
    return lower.contains('model_not_found') ||
        lower.contains('does not exist') ||
        lower.contains('not a valid model') ||
        lower.contains('invalid model') ||
        lower.contains('unknown model');
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
    try {
      final apiKey = await providers.getApiKeyForProvider(providerId);
      if (apiKey.isEmpty) return null;

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
      default:
        return false;
    }
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
