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
            'is_free': (m['pricing']?['prompt'] ?? 0) == 0,
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
            'is_free': false, // Groq models are paid
            'supports_vision': (m['id'] as String).contains('vision'),
          };
        }).toList();

        _logger.log('ModelFetcher', 'Fetched ${models.length} Groq models');\n        return models;
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

  /// Filter models based on criteria
  List<Map<String, dynamic>> filterModels({
    required List<Map<String, dynamic>> models,
    bool freeOnly = false,
    bool webSearchOnly = false,
    String? searchQuery,
  }) {
    var filtered = List<Map<String, dynamic>>.from(models);

    // Filter by free models
    if (freeOnly) {
      filtered = filtered.where((m) => m['is_free'] == true).toList();
    }

    // Filter by web search capability
    if (webSearchOnly) {
      filtered = filtered.where((m) {
        final id = m['id'].toString().toLowerCase();
        // OpenRouter models with :online capability support web search
        return id.contains(':free') || 
               id.contains('gpt-4') || 
               id.contains('gpt-3.5') ||
               id.contains('claude');
      }).toList();
    }

    // Filter by search query
    if (searchQuery != null && searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      filtered = filtered.where((m) {
        final id = (m['id'] ?? '').toString().toLowerCase();
        final name = (m['name'] ?? '').toString().toLowerCase();
        return id.contains(query) || name.contains(query);
      }).toList();
    }

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
