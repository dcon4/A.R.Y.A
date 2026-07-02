import 'package:arya/services/openai_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _customModelController = TextEditingController();
  bool _isSaved = false;
  bool _obscureKey = true;
  String _selectedModel = 'openai/gpt-4o-mini';
  bool _useCustomModel = false;

  static const List<Map<String, String>> _presetModels = [
    {'id': 'openai/gpt-4o-mini', 'label': 'GPT-4o Mini (fast, cheap)'},
    {'id': 'openai/gpt-4o', 'label': 'GPT-4o (most capable)'},
    {'id': 'google/gemini-2.0-flash-001', 'label': 'Gemini 2.0 Flash (fast)'},
    {'id': 'google/gemini-2.5-flash-preview-04-17', 'label': 'Gemini 2.5 Flash (free)'},
    {'id': 'meta-llama/llama-3.3-70b-instruct', 'label': 'Llama 3.3 70B (open)'},
    {'id': 'mistralai/mistral-7b-instruct:free', 'label': 'Mistral 7B (free tier)'},
    {'id': 'cognitivecomputations/dolphin-mixtral-8x7b:free', 'label': 'Dolphin Mixtral (free)'},
    {'id': 'microsoft/phi-3-medium-128k-instruct:free', 'label': 'Phi-3 Medium (free)'},
    {'id': 'anthropic/claude-3.5-sonnet', 'label': 'Claude 3.5 Sonnet'},
    {'id': 'anthropic/claude-3-haiku', 'label': 'Claude 3 Haiku (fast)'},
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedKey = prefs.getString('openrouter_api_key') ?? '';
    final savedModel = prefs.getString('openrouter_model') ?? 'openai/gpt-4o-mini';
    final isCustom = !_presetModels.any((m) => m['id'] == savedModel);
    setState(() {
      _apiKeyController.text = savedKey;
      _selectedModel = isCustom ? _presetModels[0]['id']! : savedModel;
      _useCustomModel = isCustom;
      _customModelController.text = isCustom ? savedModel : '';
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('openrouter_api_key', _apiKeyController.text.trim());
    final model = _useCustomModel
        ? _customModelController.text.trim()
        : _selectedModel;
    if (model.isNotEmpty) {
      await prefs.setString('openrouter_model', model);
    }
    clearCachedSettings();
    setState(() {
      _isSaved = true;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isSaved = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _customModelController.dispose();
    super.dispose();
  }

  Widget _modelTile(String id, String label, bool isSelected) {
    return InkWell(
      onTap: () {
        setState(() {
          _useCustomModel = false;
          _selectedModel = id;
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: const Color.fromRGBO(255, 87, 51, 1),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Cera Pro',
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    id,
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontFamily: 'Cera Pro',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color.fromRGBO(255, 87, 51, 1)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Settings",
          style: TextStyle(
            color: Color.fromRGBO(255, 87, 51, 1),
            fontSize: 22,
            fontWeight: FontWeight.bold,
            fontFamily: 'Cera Pro',
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            const Text(
              "OpenRouter API Key",
              style: TextStyle(
                color: Color.fromRGBO(255, 87, 51, 1),
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cera Pro',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Get your free API key at openrouter.ai/keys. ARYA needs this key to talk to the AI.",
              style: TextStyle(
                color: Color.fromRGBO(255, 138, 101, 0.8),
                fontSize: 14,
                fontFamily: 'Cera Pro',
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _apiKeyController,
              obscureText: _obscureKey,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'Cera Pro',
                fontSize: 15,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color.fromRGBO(255, 255, 255, 0.08),
                hintText: "sk-or-v1-...",
                hintStyle: TextStyle(
                  color: Colors.grey[600],
                  fontFamily: 'Cera Pro',
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: Color.fromRGBO(255, 87, 51, 0.5),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: const Color.fromRGBO(255, 87, 51, 1).withValues(alpha: 0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: Color.fromRGBO(255, 87, 51, 1),
                    width: 2,
                  ),
                ),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        _obscureKey ? Icons.visibility_off : Icons.visibility,
                        color: const Color.fromRGBO(255, 87, 51, 0.7),
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureKey = !_obscureKey;
                        });
                      },
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.paste,
                        color: Color.fromRGBO(255, 87, 51, 0.7),
                      ),
                      onPressed: () async {
                        final data = await Clipboard.getData(Clipboard.kTextPlain);
                        if (data?.text != null) {
                          _apiKeyController.text = data!.text!;
                        }
                      },
                    ),
                  ],
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              "AI Model",
              style: TextStyle(
                color: Color.fromRGBO(255, 87, 51, 1),
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cera Pro',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Models tagged (free) are available without payment on OpenRouter. Other models need a credit card on your OpenRouter account.",
              style: TextStyle(
                color: Color.fromRGBO(255, 138, 101, 0.8),
                fontSize: 14,
                fontFamily: 'Cera Pro',
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            ..._presetModels.map((m) => _modelTile(
              m['id']!,
              m['label']!,
              !_useCustomModel && _selectedModel == m['id'],
            )),
            InkWell(
              onTap: () {
                setState(() {
                  _useCustomModel = true;
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Row(
                  children: [
                    Icon(
                      _useCustomModel
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: const Color.fromRGBO(255, 87, 51, 1),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      "Custom model",
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'Cera Pro',
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_useCustomModel)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 8, bottom: 16),
                child: TextField(
                  controller: _customModelController,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Cera Pro',
                    fontSize: 15,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color.fromRGBO(255, 255, 255, 0.08),
                    hintText: "e.g. openai/gpt-4o-mini",
                    hintStyle: TextStyle(
                      color: Colors.grey[600],
                      fontFamily: 'Cera Pro',
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: const Color.fromRGBO(255, 87, 51, 1).withValues(alpha: 0.3),
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _saveSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromRGBO(255, 87, 51, 1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  _isSaved ? "Saved!" : "Save Settings",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cera Pro',
                  ),
                ),
              ),
            ),
            if (_isSaved)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Text(
                      "Settings saved.",
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 14,
                        fontFamily: 'Cera Pro',
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
