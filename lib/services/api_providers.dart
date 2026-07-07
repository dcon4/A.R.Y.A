import 'package:shared_preferences/shared_preferences.dart';

const _prefsProvider = 'api_provider';
const _prefsKey = 'api_key';
const _prefsModel = 'api_model';
const _prefsCustomBaseUrl = 'api_custom_base_url';
const _prefsWebSearch = 'web_search_enabled';

class ApiProvider {
  final String id;
  final String name;
  final String baseUrl;
  final String defaultModel;
  final List<ApiModel> models;
  final bool requiresReferer;

  const ApiProvider({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.defaultModel,
    required this.models,
    this.requiresReferer = false,
  });

  String get prefKey => '${id}_api_key';
}

class ApiModel {
  final String id;
  final String label;
  const ApiModel({required this.id, required this.label});
}

final List<ApiProvider> apiProviders = [
  ApiProvider(
    id: 'openrouter',
    name: 'OpenRouter',
    baseUrl: 'https://openrouter.ai/api/v1',
    defaultModel: '~openai/gpt-mini-latest',
    requiresReferer: true,
    models: const [
      ApiModel(id: 'openai/gpt-oss-20b:free', label: 'GPT OSS 20B (FREE)'),
      ApiModel(id: 'openai/gpt-oss-120b:free', label: 'GPT OSS 120B (FREE)'),
      ApiModel(id: 'meta-llama/llama-3.3-70b-instruct:free', label: 'Llama 3.3 70B (FREE)'),
      ApiModel(id: 'google/gemma-4-26b-a4b-it:free', label: 'Gemma 4 26B (FREE)'),
      ApiModel(id: 'google/gemma-4-31b-it:free', label: 'Gemma 4 31B (FREE)'),
      ApiModel(id: 'qwen/qwen3-coder:free', label: 'Qwen 3 Coder (FREE)'),
      ApiModel(id: 'qwen/qwen3-next-80b-a3b-instruct:free', label: 'Qwen 3 Next 80B (FREE)'),
      ApiModel(id: 'nousresearch/hermes-3-llama-3.1-405b:free', label: 'Hermes 3 405B (FREE)'),
      ApiModel(id: 'cohere/north-mini-code:free', label: 'Cohere North Mini Code (FREE)'),
      ApiModel(id: 'nvidia/nemotron-3-ultra-550b-a55b:free', label: 'Nemotron 3 Ultra 550B (FREE)'),
      ApiModel(id: 'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free', label: 'Nemotron 3 Nano Omni (FREE)'),
      ApiModel(id: 'nvidia/nemotron-3-super-120b-a12b:free', label: 'Nemotron 3 Super 120B (FREE)'),
      ApiModel(id: 'nvidia/nemotron-3.5-content-safety:free', label: 'Nemotron 3.5 Safety (FREE)'),
      ApiModel(id: 'liquid/lfm-2.5-1.2b-thinking:free', label: 'LFM 1.2B Thinking (FREE)'),
      ApiModel(id: 'liquid/lfm-2.5-1.2b-instruct:free', label: 'LFM 1.2B Instruct (FREE)'),
      ApiModel(id: 'poolside/laguna-xs.2:free', label: 'Poolside Laguna XS (FREE)'),
      ApiModel(id: 'poolside/laguna-m.1:free', label: 'Poolside Laguna M (FREE)'),
      ApiModel(id: 'cognitivecomputations/dolphin-mistral-24b-venice-edition:free', label: 'Dolphin Mistral 24B (FREE)'),
      ApiModel(id: 'meta-llama/llama-3.2-3b-instruct:free', label: 'Llama 3.2 3B (FREE)'),
      ApiModel(id: 'nvidia/nemotron-nano-12b-v2-vl:free', label: 'Nemotron Nano 12B VL (FREE)'),
      ApiModel(id: 'nvidia/nemotron-nano-9b-v2:free', label: 'Nemotron Nano 9B (FREE)'),
      ApiModel(id: '~openai/gpt-mini-latest', label: 'GPT Mini (paid, credits)'),
      ApiModel(id: 'google/gemini-3.5-flash', label: 'Gemini 3.5 Flash (paid)'),
      ApiModel(id: 'deepseek/deepseek-v4-flash', label: 'DeepSeek V4 Flash (paid)'),
      ApiModel(id: 'anthropic/claude-sonnet-5', label: 'Claude Sonnet 5 (paid)'),
    ],
  ),
  ApiProvider(
    id: 'openai',
    name: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    defaultModel: 'gpt-4o-mini',
    models: const [
      ApiModel(id: 'gpt-4o-mini', label: 'GPT-4o Mini'),
      ApiModel(id: 'gpt-4o', label: 'GPT-4o'),
      ApiModel(id: 'gpt-3.5-turbo', label: 'GPT-3.5 Turbo'),
      ApiModel(id: 'o3-mini', label: 'o3 Mini'),
    ],
  ),
  ApiProvider(
    id: 'groq',
    name: 'Groq',
    baseUrl: 'https://api.groq.com/openai/v1',
    defaultModel: 'llama3-70b-8192',
    models: const [
      ApiModel(id: 'llama3-70b-8192', label: 'Llama 3 70B'),
      ApiModel(id: 'llama3-8b-8192', label: 'Llama 3 8B'),
      ApiModel(id: 'mixtral-8x7b-32768', label: 'Mixtral 8x7B'),
      ApiModel(id: 'gemma2-9b-it', label: 'Gemma 2 9B'),
    ],
  ),
  ApiProvider(
    id: 'deepseek',
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com',
    defaultModel: 'deepseek-chat',
    models: const [
      ApiModel(id: 'deepseek-chat', label: 'DeepSeek Chat'),
      ApiModel(id: 'deepseek-reasoner', label: 'DeepSeek Reasoner'),
    ],
  ),
  ApiProvider(
    id: 'cerebras',
    name: 'Cerebras',
    baseUrl: 'https://api.cerebras.ai/v1',
    defaultModel: 'llama3.1-8b',
    models: const [
      ApiModel(id: 'llama3.1-8b', label: 'Llama 3.1 8B'),
      ApiModel(id: 'llama-3.3-70b', label: 'Llama 3.3 70B'),
      ApiModel(id: 'llama3.1-70b', label: 'Llama 3.1 70B'),
    ],
  ),
  ApiProvider(
    id: 'custom',
    name: 'Custom',
    baseUrl: '',
    defaultModel: '',
    models: const [],
  ),
];

// --- Routing config keys ---

const _routingQuickProvider = 'routing_quick_provider_id';
const _routingQuickModel = 'routing_quick_model';
const _routingReasoningProvider = 'routing_reasoning_provider_id';
const _routingReasoningModel = 'routing_reasoning_model';
const _routingCreativeProvider = 'routing_creative_provider_id';
const _routingCreativeModel = 'routing_creative_model';
const _routingCodingProvider = 'routing_coding_provider_id';
const _routingCodingModel = 'routing_coding_model';

String _routingPrefProvider(String category) =>
    'routing_${category}_provider_id';
String _routingPrefModel(String category) =>
    'routing_${category}_model';

Future<String> getRoutingProviderId(String category) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_routingPrefProvider(category)) ?? '';
}

Future<String> getRoutingModel(String category) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_routingPrefModel(category)) ?? '';
}

Future<void> setRouting(String category, String providerId, String model) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_routingPrefProvider(category), providerId);
  await prefs.setString(_routingPrefModel(category), model);
}

Future<bool> getAutoRouteEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('auto_route_enabled') ?? false;
}

Future<void> setAutoRouteEnabled(bool val) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('auto_route_enabled', val);
}

Future<String> getSelectedProviderId() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_prefsProvider) ?? 'openrouter';
}

Future<String> getApiKeyForProvider(String providerId) async {
  final provider = apiProviders.firstWhere(
    (p) => p.id == providerId,
    orElse: () => apiProviders[0],
  );
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(provider.prefKey) ?? '';
}

Future<String> getBaseUrlForProvider(String providerId) async {
  final provider = apiProviders.firstWhere(
    (p) => p.id == providerId,
    orElse: () => apiProviders[0],
  );
  if (provider.id == 'custom') {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('api_custom_base_url') ?? '';
  }
  return provider.baseUrl;
}

bool getRequiresRefererForProvider(String providerId) {
  final provider = apiProviders.firstWhere(
    (p) => p.id == providerId,
    orElse: () => apiProviders[0],
  );
  return provider.requiresReferer;
}

// --- Preference accessors ---

Future<ApiProvider> getSelectedProvider() async {
  final prefs = await SharedPreferences.getInstance();
  final id = prefs.getString(_prefsProvider) ?? 'openrouter';
  return apiProviders.firstWhere((p) => p.id == id,
      orElse: () => apiProviders[0]);
}

Future<String> getApiKey() async {
  final provider = await getSelectedProvider();
  final prefs = await SharedPreferences.getInstance();
  if (provider.id == 'openrouter') {
    return prefs.getString(provider.prefKey) ?? '';
  }
  return prefs.getString(provider.prefKey) ?? '';
}

Future<String> getSelectedModel() async {
  final provider = await getSelectedProvider();
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_prefsModel) ?? provider.defaultModel;
}

Future<String> getBaseUrl() async {
  final provider = await getSelectedProvider();
  if (provider.id == 'custom') {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsCustomBaseUrl) ?? '';
  }
  return provider.baseUrl;
}

Future<bool> getRequiresReferer() async {
  final provider = await getSelectedProvider();
  return provider.requiresReferer;
}

Future<bool> getWebSearchEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_prefsWebSearch) ?? false;
}

Future<void> setWebSearchEnabled(bool enabled) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_prefsWebSearch, enabled);
}

void clearCachedSettings() {
  // No in-memory cache in this implementation
}
