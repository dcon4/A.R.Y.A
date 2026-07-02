import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

String? _cachedApiKey;
String? _cachedModel;

Future<String> getApiKey() async {
  if (_cachedApiKey != null) return _cachedApiKey!;
  final prefs = await SharedPreferences.getInstance();
  final savedKey = prefs.getString('openrouter_api_key');
  if (savedKey != null && savedKey.isNotEmpty) {
    _cachedApiKey = savedKey;
    return savedKey;
  }
  return '';
}

Future<String> getModel() async {
  if (_cachedModel != null) return _cachedModel!;
  final prefs = await SharedPreferences.getInstance();
  final savedModel = prefs.getString('openrouter_model');
  if (savedModel != null && savedModel.isNotEmpty) {
    _cachedModel = savedModel;
    return savedModel;
  }
  return 'openai/gpt-4o-mini';
}

String getSiteUrl() {
  return 'https://github.com/4bhisheksharma/A.R.Y.A';
}

String getSiteName() {
  return 'A.R.Y.A';
}

Future<bool> hasValidApiKey() async {
  final key = await getApiKey();
  return key.isNotEmpty;
}

class OpenaiService {
  final String baseUrl = 'https://openrouter.ai/api/v1';

  final String systemPrompt = '''
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

  Future<String?> chatGPTAPI(String prompt) async {
    try {
      final apiKey = await getApiKey();
      if (apiKey.isEmpty) {
        return 'Please add your OpenRouter API key in Settings first.';
      }
      final model = await getModel();
      final response = await http.post(
        Uri.parse('$baseUrl/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
          'HTTP-Referer': getSiteUrl(),
          'X-Title': getSiteName(),
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': prompt},
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'];
        return content;
      } else {
        print('Error: ${response.statusCode}');
        print('Response: ${response.body}');
        return 'Sorry, I encountered an error. Please try again.';
      }
    } catch (e) {
      print('Exception: $e');
      return 'Sorry, something went wrong. Please check your connection.';
    }
  }
}
