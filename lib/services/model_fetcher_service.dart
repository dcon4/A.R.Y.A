import 'dart:convert';
import 'package:arya/services/debug_logger.dart';
import 'package:http/http.dart' as http;

class ModelFetcherService {
  final _logger = DebugLogger();

  /// Fetch models from OpenRouter
  Future<List<Map<String, dynamic>>> fetchOpenRouterModels(String apiKey) async {
    try {
      _logger.log('ModelFetcher', 'Fetching models from OpenRouter...');
      
      final response = await http.get(
        Uri.parse('https://openrouter.ai/api/v1/models'),
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models = (data['data'] as List).map((m) {
          return {
            'id': m['id'] ?? '',
            'name': m['name'] ?? m['id'] ?? 'Unknown',
            'pricing': m['pricing'] ?? {},
            'context_length': m['context_length'] ?? 0,
            'description': m['description'] ?? '',
            'is_free': double.tryParse(m['pricing']?['prompt']?.toString() ?? '0') == 0.0,
            'supports_vision': m['architecture']?['modality']?.contains('image') ?? false,
          };
        }).toList();

        _logger.log('ModelFetcher', 'Fetched ${models.length} OpenRouter models');
        return models;
      } else {
        _logger.error('ModelFetcher', 'OpenRouter API error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      _logger.error('ModelFetcher', 'Failed to fetch OpenRouter models', e);
      return [];
    }
  }

  /// Fetch models from OpenAI
  Future<List<Map<String, dynamic>>> fetchOpenAIModels(String apiKey) async {
    try {
      _logger.log('ModelFetcher', 'Fetching models from OpenAI...');
      
      final response = await http.get(
        Uri.parse('https://api.openai.com/v1/models'),
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models = (data['data'] as List).map((m) {
          return {
            'id': m['id'] ?? '',
            'name': m['id'] ?? 'Unknown',
            'created': m['created'] ?? 0,
            'owned_by': m['owned_by'] ?? '',
            'is_free': false, // OpenAI models are paid
            'supports_vision': (m['id'] as String).contains('vision'),
          };
        }).toList();

        _logger.log('ModelFetcher', 'Fetched ${models.length} OpenAI models');
        return models;
      } else {
        _logger.error('ModelFetcher', 'OpenAI API error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      _logger.error('ModelFetcher', 'Failed to fetch OpenAI models', e);
      return [];
    }
  }

  /// Fetch models from Groq
  Future<List<Map<String, dynamic>>> fetchGroqModels(String apiKey) async {
    try {
      _logger.log('ModelFetcher', 'Fetching models from Groq...');
      
      final response = await http.get(
        Uri.parse('https://api.groq.com/openai/v1/models'),
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models = (data['data'] as List).map((m) {
          return {
            'id': m['id'] ?? '',
            'name': m['id'] ?? 'Unknown',
            'created': m['created'] ?? 0,
            // Groq's developer tier is free — mark models free so the filter works.
            'is_free': true,
            'supports_vision': (m['id'] as String).contains('vision'),
          };
        }).toList();

        _logger.log('ModelFetcher', 'Fetched ${models.length} Groq models');
        return models;
      } else {
        _logger.error('ModelFetcher', 'Groq API error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      _logger.error('ModelFetcher', 'Failed to fetch Groq models', e);
      return [];
    }
  }

  /// Fetch models from DeepSeek
  Future<List<Map<String, dynamic>>> fetchDeepSeekModels(String apiKey) async {
    try {
      _logger.log('ModelFetcher', 'Fetching models from DeepSeek...');
      
      final response = await http.get(
        Uri.parse('https://api.deepseek.com/models'),
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models = (data['data'] as List).map((m) {
          return {
            'id': m['id'] ?? '',
            'name': m['name'] ?? m['id'] ?? 'Unknown',
            'is_free': false, // DeepSeek models are paid
            'supports_vision': (m['id'] as String).contains('vision'),
          };
        }).toList();

        _logger.log('ModelFetcher', 'Fetched ${models.length} DeepSeek models');
        return models;
      } else {
        _logger.error('ModelFetcher', 'DeepSeek API error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      _logger.error('ModelFetcher', 'Failed to fetch DeepSeek models', e);
      return [];
    }
  }

  /// Fetch models from Cerebras (OpenAI-compatible API)
  Future<List<Map<String, dynamic>>> fetchCerebrasModels(String apiKey) async {
    try {
      _logger.log('ModelFetcher', 'Fetching models from Cerebras...');
      
      final response = await http.get(
        Uri.parse('https://api.cerebras.ai/v1/models'),
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models = (data['data'] as List).map((m) {
          return {
            'id': m['id'] ?? '',
            'name': m['id'] ?? 'Unknown',
            'is_free': false,
            'supports_vision': (m['id'] as String).contains('vision'),
          };
        }).toList();

        _logger.log('ModelFetcher', 'Fetched ${models.length} Cerebras models');
        return models;
      } else {
        _logger.error('ModelFetcher', 'Cerebras API error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      _logger.error('ModelFetcher', 'Failed to fetch Cerebras models', e);
      return [];
    }
  }

  /// Fetch models from NVIDIA NIM (public list, no key required)
  Future<List<Map<String, dynamic>>> fetchNvidiaNimModels(
      [String apiKey = '']) async {
    try {
      _logger.log('ModelFetcher', 'Fetching models from NVIDIA NIM...');

      final headers = <String, String>{};
      if (apiKey.isNotEmpty) {
        headers['Authorization'] = 'Bearer $apiKey';
      }
      final response = await http
          .get(
            Uri.parse('https://integrate.api.nvidia.com/v1/models'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models = (data['data'] as List).map((m) {
          return {
            'id': m['id'] ?? '',
            'name': m['id'] ?? 'Unknown',
            'is_free': false, // NIM is paid per token
            'supports_vision': false,
          };
        }).toList();

        _logger.log('ModelFetcher', 'Fetched ${models.length} NIM models');
        return models;
      } else {
        _logger.error('ModelFetcher', 'NIM API error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      _logger.error('ModelFetcher', 'Failed to fetch NIM models', e);
      return [];
    }
  }

  /// Fetch models from Kilo's gateway (open list, key optional)
  Future<List<Map<String, dynamic>>> fetchKiloCodeModels(String apiKey) async {
    try {
      _logger.log('ModelFetcher', 'Fetching models from Kilo Code...');

      final response = await http.get(
        Uri.parse('https://api.kilo.ai/api/gateway/models'),
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models = (data['data'] as List).map((m) {
          return {
            'id': m['id'] ?? '',
            'name': m['id'] ?? 'Unknown',
            'created': m['created'] ?? 0,
            // Kilo's gateway mixes free and paid models; free ones are
            // marked ":free" or carry "free" in the id (kilo-auto/free).
            'is_free': m['id']?.toString().toLowerCase().contains('free') ?? false,
            'supports_vision': (m['id'] as String).contains('vision'),
          };
        }).toList();

        _logger.log('ModelFetcher', 'Fetched ${models.length} Kilo models');
        return models;
      } else {
        _logger.error('ModelFetcher', 'Kilo Code API error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      _logger.error('ModelFetcher', 'Failed to fetch Kilo Code models', e);
      return [];
    }
  }

  /// Fetch models from Ollama Cloud (ollama.com).
  ///
  /// The list is public, so it works without a key too; chat itself always
  /// needs one. Response is OpenAI-style: {"data": [{"id": "..."}]}.
  Future<List<Map<String, dynamic>>> fetchOllamaModels(String apiKey) async {
    try {
      _logger.log('ModelFetcher', 'Fetching models from Ollama...');

      final response = await http.get(
        Uri.parse('https://ollama.com/v1/models'),
        headers: {
          if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models = (data['data'] as List).map((m) {
          final id = (m['id'] ?? '').toString();
          return {
            'id': id,
            'name': id,
            'is_free': false,
            'supports_vision': false,
          };
        }).toList();

        _logger.log('ModelFetcher', 'Fetched ${models.length} Ollama models');
        return models;
      } else {
        _logger.error('ModelFetcher', 'Ollama API error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      _logger.error('ModelFetcher', 'Failed to fetch Ollama models', e);
      return [];
    }
  }

  /// Fetch models from Venice.ai (api.venice.ai). The list is readable
  /// without a key; per-token pricing and vision support come along too.
  Future<List<Map<String, dynamic>>> fetchVeniceModels(String apiKey) async {
    try {
      _logger.log('ModelFetcher', 'Fetching models from Venice...');

      final response = await http.get(
        Uri.parse('https://api.venice.ai/api/v1/models'),
        headers: {
          if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models = (data['data'] as List).map((m) {
          final id = (m['id'] ?? '').toString();
          final spec = m['model_spec'] ?? const {};
          final pricing = (spec['pricing'] ?? const {})['input'] ?? const {};
          final caps = spec['capabilities'] ?? const {};
          final usd = ((pricing['usd'] as num?) ?? 1).toDouble();
          return {
            'id': id,
            'name': id,
            'is_free': usd == 0,
            'supports_vision': caps['supportsVision'] == true,
          };
        }).toList();

        _logger.log('ModelFetcher', 'Fetched ${models.length} Venice models');
        return models;
      } else {
        _logger.error('ModelFetcher', 'Venice API error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      _logger.error('ModelFetcher', 'Failed to fetch Venice models', e);
      return [];
    }
  }

  /// Fetch models from Requesty (router.requesty.ai). The list is readable
  /// without a key; free models carry zero input and output prices.
  Future<List<Map<String, dynamic>>> fetchRequestyModels(String apiKey) async {
    try {
      _logger.log('ModelFetcher', 'Fetching models from Requesty...');

      final response = await http.get(
        Uri.parse('https://router.requesty.ai/v1/models'),
        headers: {
          if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models = (data['data'] as List).map((m) {
          final id = (m['id'] ?? '').toString();
          final input = (m['input_price'] as num?) ?? 1;
          final output = (m['output_price'] as num?) ?? 1;
          return {
            'id': id,
            'name': id,
            'is_free': input == 0 && output == 0,
            'supports_vision': m['supports_vision'] == true,
          };
        }).toList();

        _logger.log('ModelFetcher', 'Fetched ${models.length} Requesty models');
        return models;
      } else {
        _logger.error('ModelFetcher', 'Requesty API error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      _logger.error('ModelFetcher', 'Failed to fetch Requesty models', e);
      return [];
    }
  }

  /// Fetch models from Mistral (api.mistral.ai). The list needs a key;
  /// the free plan is rate limited but bills nothing.
  Future<List<Map<String, dynamic>>> fetchMistralModels(String apiKey) async {
    try {
      _logger.log('ModelFetcher', 'Fetching models from Mistral...');

      final response = await http.get(
        Uri.parse('https://api.mistral.ai/v1/models'),
        headers: {
          if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models = (data['data'] as List).map((m) {
          final id = (m['id'] ?? '').toString();
          return {
            'id': id,
            'name': id,
            'is_free': true,
            'supports_vision': false,
          };
        }).where((m) => (m['id'] as String).isNotEmpty).toList();

        _logger.log('ModelFetcher', 'Fetched ${models.length} Mistral models');
        return models;
      } else {
        _logger.error('ModelFetcher', 'Mistral API error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      _logger.error('ModelFetcher', 'Failed to fetch Mistral models', e);
      return [];
    }
  }

  /// Fetch models from Zenith (api.zenllm.org). The list is readable without
  /// a key; pricing is prepaid micro-USD per token (nothing free today).
  Future<List<Map<String, dynamic>>> fetchZenithModels(String apiKey) async {
    try {
      _logger.log('ModelFetcher', 'Fetching models from Zenith...');

      final response = await http.get(
        Uri.parse('https://api.zenllm.org/v1/models'),
        headers: {
          if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models = (data['data'] as List).map((m) {
          final id = (m['id'] ?? '').toString();
          final pricing = m['pricing'] ?? const {};
          final perMtok = (pricing['input_per_mtok'] as num?) ?? 1;
          final modalities =
              (m['architecture']?['input_modalities'] as List?) ?? const [];
          return {
            'id': id,
            'name': (m['display_name'] ?? id).toString(),
            'is_free': perMtok == 0,
            'supports_vision': modalities.contains('image'),
          };
        }).toList();

        _logger.log('ModelFetcher', 'Fetched ${models.length} Zenith models');
        return models;
      } else {
        _logger.error('ModelFetcher', 'Zenith API error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      _logger.error('ModelFetcher', 'Failed to fetch Zenith models', e);
      return [];
    }
  }

  /// Filter models based on criteria
  List<Map<String, dynamic>> filterModels({
    required List<Map<String, dynamic>> models,
    bool freeOnly = false,
    bool webSearchOnly = false,
    String? searchQuery,
  }) {
    var filtered = List<Map<String, dynamic>>.from(models);

    _logger.verbose('ModelFetcher', 'Filter start: ${models.length} total models');

    // Filter by free models
    if (freeOnly) {
      final before = filtered.length;
      filtered = filtered.where((m) {
        final isFree = m['is_free'] == true;
        if (!isFree) {
          _logger.verbose('ModelFetcher', '  Excluding paid: ${m['id']} (is_free=${m['is_free']})');
        }
        return isFree;
      }).toList();
      _logger.log('ModelFetcher', 'Free filter: $before -> ${filtered.length} models');
    }

    // Filter by web search capability
    // On OpenRouter, any model supports :online, so web search is universal.
    // This filter simply shows all models when enabled (placeholder for future).
    if (webSearchOnly) {
      // All models pass through - any OpenRouter model can use :online
    }

    // Filter by search query
    if (searchQuery != null && searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      final before = filtered.length;
      filtered = filtered.where((m) {
        final id = (m['id'] ?? '').toString().toLowerCase();
        final name = (m['name'] ?? '').toString().toLowerCase();
        return id.contains(query) || name.contains(query);
      }).toList();
      _logger.log('ModelFetcher', 'Search filter: $before -> ${filtered.length} models');
    }

    _logger.log('ModelFetcher', 'Final filtered: ${filtered.length}/${models.length} models');
    return filtered;
  }

  /// Sort models by name
  List<Map<String, dynamic>> sortModels(
    List<Map<String, dynamic>> models, {
    bool ascending = true,
  }) {
    final sorted = List<Map<String, dynamic>>.from(models);
    sorted.sort((a, b) {
      final aName = (a['name'] ?? a['id'] ?? '').toString();
      final bName = (b['name'] ?? b['id'] ?? '').toString();
      return ascending 
        ? aName.compareTo(bName)
        : bName.compareTo(aName);
    });
    return sorted;
  }
}