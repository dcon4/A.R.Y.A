import 'dart:convert';
import 'package:arya/services/api_providers.dart' as providers;
import 'package:arya/services/brave_search_service.dart';
import 'package:arya/services/debug_logger.dart';
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

  static Future<String> getSystemPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('system_prompt') ?? defaultSystemPrompt;
  }

  static Future<void> setSystemPrompt(String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('system_prompt', prompt);
  }

  final _logger = DebugLogger();

  Future<String?> chatGPTAPI(String prompt, {List<Map<String, String>>? history}) async {
    try {
      final apiKey = await getApiKey();
      if (apiKey.isEmpty) {
        _logger.log('OpenAIService', 'API call blocked - no API key set');
        return 'Please add your API key in Settings first.';
      }

      var model = await getModel();
      final baseUrl = await getBaseUrlCached();
      if (baseUrl.isEmpty) {
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

      final webSearch = !braveSearch && await providers.getWebSearchEnabled();
      if (webSearch && !model.contains(':online')) {
        model = '$model:online';
      }

      final requiresReferer = await getRequiresRefererCached();
      _logger.log('OpenAIService', 'Sending request to $baseUrl model=$model');

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      };
      if (requiresReferer) {
        headers['HTTP-Referer'] = getSiteUrl();
        headers['X-Title'] = getSiteName();
      }

      final sysPrompt = await getSystemPrompt();
      final messages = <Map<String, String>>[
        {'role': 'system', 'content': sysPrompt},
      ];
      if (history != null) {
        messages.addAll(history);
      }
      if (searchResults != null && searchResults.isNotEmpty) {
        final context = BraveSearchService().formatResults(searchResults);
        messages.add({'role': 'system', 'content': context});
      }
      messages.add({'role': 'user', 'content': prompt});

      final response = await http.post(
        Uri.parse('$baseUrl/chat/completions'),
        headers: headers,
        body: jsonEncode({
          'model': model,
          'messages': messages,
        }),
      );

      if (response.statusCode == 200) {
        _logger.log('OpenAIService', 'API response OK (${response.body.length} chars)');
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'];
        return content;
      } else {
        _logger.error('OpenAIService', 'API error HTTP ${response.statusCode}');
        _logger.verbose('OpenAIService', 'Response body: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}');
        String detail;
        try {
          final err = jsonDecode(response.body);
          detail = err['error']['message'] ?? 'HTTP ${response.statusCode}';
        } catch (_) {
          detail = 'HTTP ${response.statusCode}';
        }
        return 'API error: $detail';
      }
    } catch (e) {
      _logger.error('OpenAIService', 'Request exception', e);
      return 'Sorry, something went wrong. Please check your connection.';
    }
  }
}
