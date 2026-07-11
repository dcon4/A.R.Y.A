import 'dart:io';
import 'package:arya/models/memory_entry.dart';
import 'package:arya/services/api_providers.dart' as providers;
import 'package:arya/services/brave_search_service.dart';
import 'package:arya/services/background_service.dart';
import 'package:arya/services/debug_logger.dart';
import 'package:arya/services/memory_service.dart';
import 'package:arya/services/openai_service.dart';
import 'package:arya/services/save_directory_picker.dart';
import 'package:arya/services/settings_service.dart';
import 'package:arya/services/wake_word_service.dart';
import 'package:arya/widgets/model_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:share_plus/share_plus.dart';
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
  final TextEditingController _customBaseUrlController = TextEditingController();
  final TextEditingController _systemPromptController = TextEditingController();
  bool _isSaved = false;
  bool _obscureKey = true;
  String _selectedProviderId = 'openrouter';
  int _announceMode = 0;
  int _listeningDuration = 30;
  int _pauseDuration = 3;
  bool _autoRouteEnabled = false;
  int _memoryCount = 0;
  String _selectedModelId = '';
  bool _useCustomModel = false;
  List<providers.ApiModel> _currentModels = [];

  providers.ApiProvider get _selectedProvider {
    return providers.apiProviders.firstWhere(
      (p) => p.id == _selectedProviderId,
      orElse: () => providers.apiProviders[0],
    );
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedProviderId = prefs.getString('api_provider') ?? 'openrouter';
    final provider = providers.apiProviders.firstWhere(
      (p) => p.id == savedProviderId,
      orElse: () => providers.apiProviders[0],
    );

    final savedKey = prefs.getString(provider.prefKey) ?? '';
    final savedModel = prefs.getString('api_model') ?? provider.defaultModel;
    final isCustomModel = !provider.models.any((m) => m.id == savedModel);
    final savedCustomBaseUrl = prefs.getString('api_custom_base_url') ?? '';
    final savedSystemPrompt = prefs.getString('system_prompt') ?? '';

    setState(() {
      _selectedProviderId = savedProviderId;
      _systemPromptController.text = savedSystemPrompt;
      _apiKeyController.text = savedKey;
      _selectedModelId = isCustomModel ? provider.defaultModel : savedModel;
      _useCustomModel = isCustomModel;
      _customModelController.text = isCustomModel ? savedModel : '';
      _customBaseUrlController.text = savedCustomBaseUrl;
      _currentModels = provider.models;
      _announceMode = prefs.getInt('mic_announcement_mode') ?? 0;
      _listeningDuration = prefs.getInt('listening_duration_seconds') ?? 30;
      _pauseDuration = prefs.getInt('pause_duration_seconds') ?? 3;
      _autoRouteEnabled = prefs.getBool('auto_route_enabled') ?? false;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_provider', _selectedProviderId);
    final provider = _selectedProvider;
    await prefs.setString(provider.prefKey, _apiKeyController.text.trim());

    final model = _useCustomModel
        ? _customModelController.text.trim()
        : _selectedModelId;
    if (model.isNotEmpty) {
      await prefs.setString('api_model', model);
    }

    if (provider.id == 'custom') {
      await prefs.setString('api_custom_base_url', _customBaseUrlController.text.trim());
    }

    await prefs.setString('system_prompt', _systemPromptController.text.trim());
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

  void _onProviderChanged(String? newId) {
    if (newId == null || newId == _selectedProviderId) return;
    final newProvider = providers.apiProviders.firstWhere(
      (p) => p.id == newId,
      orElse: () => providers.apiProviders[0],
    );
    SharedPreferences.getInstance().then((prefs) {
      final savedKey = prefs.getString(newProvider.prefKey) ?? '';
      String savedCustomUrl = '';
      if (newId == 'custom') {
        savedCustomUrl = prefs.getString('api_custom_base_url') ?? '';
      }
      setState(() {
        _selectedProviderId = newId;
        _selectedModelId = newProvider.defaultModel;
        _useCustomModel = false;
        _customModelController.clear();
        _currentModels = newProvider.models;
        _apiKeyController.text = savedKey;
        if (newId == 'custom') {
          _customBaseUrlController.text = savedCustomUrl;
        }
      });
    });
  }

  void _shareLog(BuildContext context) async {
    final logger = DebugLogger();
    final path = logger.getLogFilePath();
    if (path == null) {
      _showSnack(context, 'Log not yet initialized');
      return;
    }
    final file = File(path);
    if (!await file.exists()) {
      _showSnack(context, 'Log file not found');
      return;
    }
    try {
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'ARYA debug log',
        text: 'ARYA debug log - ${DateTime.now()}',
      );
    } catch (e) {
      _showSnack(context, 'Share failed: $e');
    }
  }

  void _showSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _customModelController.dispose();
    _customBaseUrlController.dispose();
    super.dispose();
  }

  String _providerHintText(String id) {
    switch (id) {
      case 'openrouter': return 'sk-or-v1-...';
      case 'openai': return 'sk-...';
      case 'groq': return 'gsk_...';
      case 'deepseek': return 'sk-...';
      case 'cerebras': return 'cerebras_...';
      default: return 'API key';
    }
  }

  String _providerDescription(String id) {
    switch (id) {
      case 'openrouter': return 'Get your free API key at openrouter.ai/keys. Access many models through one provider.';
      case 'openai': return 'Get your API key at platform.openai.com/api-keys.';
      case 'groq': return 'Get your free API key at console.groq.com/keys. Fast inference for open models.';
      case 'deepseek': return 'Get your API key at platform.deepseek.com/api-keys.';
      case 'cerebras': return 'Get your API key at cloud.cerebras.ai. Fast inference for open models via OpenAI-compatible API.';
      default: return 'Enter the base URL and API key for your custom provider.';
    }
  }

  Widget _buildProviderSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "AI Provider",
          style: TextStyle(
            color: Color.fromRGBO(255, 87, 51, 1),
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'Cera Pro',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _providerDescription(_selectedProviderId),
          style: const TextStyle(
            color: Color.fromRGBO(255, 138, 101, 0.8),
            fontSize: 14,
            fontFamily: 'Cera Pro',
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color.fromRGBO(255, 255, 255, 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color.fromRGBO(255, 87, 51, 1).withValues(alpha: 0.3),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedProviderId,
              isExpanded: true,
              dropdownColor: Colors.grey[900],
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'Cera Pro',
                fontSize: 15,
              ),
              items: providers.apiProviders.map((p) {
                return DropdownMenuItem(
                  value: p.id,
                  child: Text(p.name),
                );
              }).toList(),
              onChanged: _onProviderChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildApiKeyField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text(
          "${_selectedProvider.name} API Key",
          style: const TextStyle(
            color: Color.fromRGBO(255, 87, 51, 1),
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'Cera Pro',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _providerDescription(_selectedProviderId),
          style: const TextStyle(
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
            hintText: _providerHintText(_selectedProviderId),
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
      ],
    );
  }

  Widget _buildCustomBaseUrlField() {
    if (_selectedProviderId != 'custom') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: TextField(
        controller: _customBaseUrlController,
        style: const TextStyle(
          color: Colors.white,
          fontFamily: 'Cera Pro',
          fontSize: 15,
        ),
        decoration: InputDecoration(
          filled: true,
          fillColor: const Color.fromRGBO(255, 255, 255, 0.08),
          hintText: "https://api.example.com/v1",
          hintStyle: TextStyle(
            color: Colors.grey[600],
            fontFamily: 'Cera Pro',
          ),
          labelText: "Base URL",
          labelStyle: const TextStyle(
            color: Color.fromRGBO(255, 87, 51, 1),
            fontFamily: 'Cera Pro',
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: const Color.fromRGBO(255, 87, 51, 1).withValues(alpha: 0.3),
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
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildSystemPromptSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "System Prompt",
          style: TextStyle(
            color: Color.fromRGBO(255, 87, 51, 1),
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'Cera Pro',
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "Instructions given to the AI before every conversation. Leave empty for the default prompt.",
          style: TextStyle(
            color: Color.fromRGBO(255, 138, 101, 0.8),
            fontSize: 14,
            fontFamily: 'Cera Pro',
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _systemPromptController,
          maxLines: 8,
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'Cera Pro',
            fontSize: 14,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color.fromRGBO(255, 255, 255, 0.08),
            hintText: "Enter custom system prompt...",
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
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 16,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSaveButton() {
    return Column(
      children: [
        const SizedBox(height: 20),
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
            padding: EdgeInsets.only(top: 12, bottom: 8),
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
    );
  }

  Widget _buildModelSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        const Divider(color: Color.fromRGBO(255, 87, 51, 0.3)),
        const SizedBox(height: 16),
        const Text(
          "Model",
          style: TextStyle(
            color: Color.fromRGBO(255, 87, 51, 1),
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'Cera Pro',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _selectedProviderId == 'custom'
              ? "Type a model name for your custom provider."
              : "Select a model or type a custom one below. The dynamic list fetches models from the provider API when a valid key is saved.",
          style: const TextStyle(
            color: Color.fromRGBO(255, 138, 101, 0.8),
            fontSize: 14,
            fontFamily: 'Cera Pro',
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        if (_selectedProviderId != 'custom' && _apiKeyController.text.isNotEmpty)
          ModelSelector(
            key: ValueKey(_selectedProviderId),
            providerId: _selectedProviderId,
            apiKey: _apiKeyController.text.trim(),
            selectedModelId: _useCustomModel ? '' : _selectedModelId,
            onModelSelected: (modelId) {
              setState(() {
                _useCustomModel = false;
                _selectedModelId = modelId;
              });
              _saveSettings();
            },
          ),
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
                hintText: _selectedProviderId == 'openrouter'
                    ? "e.g. ~openai/gpt-mini-latest"
                    : "e.g. gpt-4o-mini",
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
      ],
    );
  }

  Widget _buildModelRoutingSection() {
    return StatefulBuilder(
      builder: (context, setInnerState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Model Routing",
              style: TextStyle(
                color: Color.fromRGBO(255, 87, 51, 1),
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cera Pro',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "ARYA automatically picks the best model based on your question. When off, always uses your default model. You can still switch providers manually.",
              style: TextStyle(
                color: Color.fromRGBO(255, 138, 101, 0.8),
                fontSize: 14,
                fontFamily: 'Cera Pro',
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _autoRouteEnabled
                        ? "Auto-route is on"
                        : "Auto-route is off",
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Cera Pro',
                      fontSize: 14,
                    ),
                  ),
                ),
                Switch(
                  value: _autoRouteEnabled,
                  onChanged: (val) async {
                    await providers.setAutoRouteEnabled(val);
                    if (mounted) setState(() => _autoRouteEnabled = val);
                    setInnerState(() {});
                  },
                  activeColor: const Color.fromRGBO(255, 87, 51, 1),
                ),
              ],
            ),
            if (_autoRouteEnabled) ...[
              const SizedBox(height: 12),
              _routingCategoryRow("Quick", "quick", "what is, who is, when, weather"),
              _routingCategoryRow("Reasoning", "reasoning", "why, explain, compare, analyze"),
              _routingCategoryRow("Creative", "creative", "write, story, poem, describe"),
              _routingCategoryRow("Coding", "coding", "code, function, bug, python, api"),
            ],
          ],
        );
      },
    );
  }

  Widget _routingCategoryRow(String label, String category, String examples) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Cera Pro',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  examples,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontFamily: 'Cera Pro',
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 36,
              child: FutureBuilder<String>(
                future: providers.getRoutingModel(category),
                builder: (context, snapshot) {
                  final current = snapshot.data ?? '';
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color.fromRGBO(255, 255, 255, 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        current.isNotEmpty ? current : '(default)',
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'Cera Pro',
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemorySection() {
    return StatefulBuilder(
      builder: (context, setInnerState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Memory",
              style: TextStyle(
                color: Color.fromRGBO(255, 87, 51, 1),
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cera Pro',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "ARYA remembers facts, preferences, and learnings across conversations. Say 'remember I like pizza' or 'what do you remember?'",
              style: TextStyle(
                color: Color.fromRGBO(255, 138, 101, 0.8),
                fontSize: 14,
                fontFamily: 'Cera Pro',
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            FutureBuilder<int>(
              future: MemoryService.instance.load().then((_) => MemoryService.instance.count),
              builder: (context, snapshot) {
                final count = snapshot.data ?? 0;
                return Text(
                  "$count / 1000 memories used",
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontFamily: 'Cera Pro',
                    fontSize: 14,
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await MemoryService.instance.load();
                        final all = MemoryService.instance.entries;
                        if (all.isEmpty) {
                          _showSnack(context, 'No memories to show');
                          return;
                        }
                        final text = all.map((e) => e.content).join('. ');
                        _showSnack(context, text.length > 200
                            ? '${text.substring(0, 200)}...'
                            : text);
                      },
                      icon: const Icon(
                        Icons.menu_book,
                        size: 16,
                        color: Color.fromRGBO(255, 87, 51, 1),
                      ),
                      label: const Text(
                        "Read",
                        style: TextStyle(
                          color: Color.fromRGBO(255, 87, 51, 1),
                          fontFamily: 'Cera Pro',
                          fontSize: 13,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: const Color.fromRGBO(255, 87, 51, 1).withValues(alpha: 0.5),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await MemoryService.instance.clearAll();
                        setInnerState(() {});
                        _showSnack(context, 'All memories cleared');
                      },
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 16,
                        color: Color.fromRGBO(255, 87, 51, 1),
                      ),
                      label: const Text(
                        "Clear",
                        style: TextStyle(
                          color: Color.fromRGBO(255, 87, 51, 1),
                          fontFamily: 'Cera Pro',
                          fontSize: 13,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: const Color.fromRGBO(255, 87, 51, 1).withValues(alpha: 0.5),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildSettingsBackupSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Settings Backup",
          style: TextStyle(
            color: Color.fromRGBO(255, 87, 51, 1),
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'Cera Pro',
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "Export all settings (API keys, models, routing, TTS, etc.) to an encrypted file. Import on another device to avoid re-entering everything.",
          style: TextStyle(
            color: Color.fromRGBO(255, 138, 101, 0.8),
            fontSize: 14,
            fontFamily: 'Cera Pro',
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 40,
                child: OutlinedButton.icon(
                  onPressed: _exportEncryptedSettings,
                  icon: const Icon(
                    Icons.file_upload_outlined,
                    size: 16,
                    color: Color.fromRGBO(255, 87, 51, 1),
                  ),
                  label: const Text(
                    "Export",
                    style: TextStyle(
                      color: Color.fromRGBO(255, 87, 51, 1),
                      fontFamily: 'Cera Pro',
                      fontSize: 13,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: const Color.fromRGBO(255, 87, 51, 1).withValues(alpha: 0.5),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 40,
                child: OutlinedButton.icon(
                  onPressed: _importEncryptedSettings,
                  icon: const Icon(
                    Icons.file_download_outlined,
                    size: 16,
                    color: Color.fromRGBO(255, 87, 51, 1),
                  ),
                  label: const Text(
                    "Import",
                    style: TextStyle(
                      color: Color.fromRGBO(255, 87, 51, 1),
                      fontFamily: 'Cera Pro',
                      fontSize: 13,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: const Color.fromRGBO(255, 87, 51, 1).withValues(alpha: 0.5),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _exportEncryptedSettings() async {
    final passphraseController = TextEditingController();
    final confirmController = TextEditingController();
    final passphrase = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Encrypt Settings',
          style: TextStyle(
            color: Color.fromRGBO(255, 87, 51, 1),
            fontFamily: 'Cera Pro',
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter a passphrase to encrypt your settings file. You will need this passphrase to import on another device.',
              style: TextStyle(
                color: Colors.white70,
                fontFamily: 'Cera Pro',
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passphraseController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Passphrase',
                border: OutlineInputBorder(),
                labelStyle: TextStyle(color: Colors.white70),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: confirmController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Confirm passphrase',
                border: OutlineInputBorder(),
                labelStyle: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: Colors.grey,
                fontFamily: 'Cera Pro',
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (passphraseController.text.isEmpty) {
                _showSnack(ctx, 'Passphrase cannot be empty');
                return;
              }
              if (passphraseController.text != confirmController.text) {
                _showSnack(ctx, 'Passphrases do not match');
                return;
              }
              Navigator.pop(ctx, passphraseController.text);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromRGBO(255, 87, 51, 1),
              foregroundColor: Colors.white,
            ),
            child: const Text(
              'Export',
              style: TextStyle(fontFamily: 'Cera Pro'),
            ),
          ),
        ],
      ),
    );
    if (passphrase == null) return;
    try {
      _showSnack(context, 'Exporting settings...');
      final ok = await SettingsService.exportToFile(passphrase);
      if (ok) {
        _showSnack(context, 'Settings exported successfully');
      } else {
        _showSnack(context, 'Export cancelled or failed');
      }
    } catch (e) {
      DebugLogger().error('SettingsScreen', 'Export failed', e);
      _showSnack(context, 'Export failed. Check debug log.');
    }
  }
 
  Future<void> _importEncryptedSettings() async {
    final passphraseController = TextEditingController();
    final passphrase = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Decrypt Settings',
          style: TextStyle(
            color: Color.fromRGBO(255, 87, 51, 1),
            fontFamily: 'Cera Pro',
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter the passphrase used when the settings were exported.',
              style: TextStyle(
                color: Colors.white70,
                fontFamily: 'Cera Pro',
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passphraseController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Passphrase',
                border: OutlineInputBorder(),
                labelStyle: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: Colors.grey,
                fontFamily: 'Cera Pro',
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (passphraseController.text.isEmpty) {
                _showSnack(ctx, 'Passphrase cannot be empty');
                return;
              }
              Navigator.pop(ctx, passphraseController.text);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromRGBO(255, 87, 51, 1),
              foregroundColor: Colors.white,
            ),
            child: const Text(
              'Import',
              style: TextStyle(fontFamily: 'Cera Pro'),
            ),
          ),
        ],
      ),
    );
    if (passphrase == null) return;
    try {
      _showSnack(context, 'Importing settings...');
      final settings = await SettingsService.importFromFile(passphrase);
      if (settings == null) {
        _showSnack(context, 'Import cancelled');
        return;
      }
      if (settings.isEmpty) {
        _showSnack(context, 'File contains no settings. Nothing to import.');
        return;
      }
      await SettingsService.applyAllSettings(settings);
      _showSnack(context, 'Settings imported successfully. Please restart ARYA.');
    } catch (e) {
      DebugLogger().error('SettingsScreen', 'Import failed', e);
      _showSnack(context, 'Import failed. Check debug log.');
    }
  }

  Widget _buildWakeWordSection() {
    return StatefulBuilder(
      builder: (context, setInnerState) {
        final ww = WakeWordService.instance;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Wake Word Detection",
              style: TextStyle(
                color: Color.fromRGBO(255, 87, 51, 1),
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cera Pro',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Say 'hey rhasspy' to trigger the mic without touching the phone. Uses openWakeWord on-device detection.",
              style: TextStyle(
                color: Color.fromRGBO(255, 138, 101, 0.8),
                fontSize: 14,
                fontFamily: 'Cera Pro',
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    ww.isRunning ? "Wake word detection is active" : "Wake word detection is off",
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Cera Pro',
                      fontSize: 14,
                    ),
                  ),
                ),
                Switch(
                  value: ww.isRunning,
                  onChanged: (val) async {
                    if (val) {
                      await ww.start();
                    } else {
                      await ww.stop();
                    }
                    setInnerState(() {});
                    setState(() {});
                  },
                  activeColor: const Color.fromRGBO(255, 87, 51, 1),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text(
                  "Sensitivity",
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'Cera Pro',
                    fontSize: 14,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: ww.threshold,
                    min: 0.1,
                    max: 0.9,
                    divisions: 8,
                    activeColor: const Color.fromRGBO(255, 87, 51, 1),
                    inactiveColor: const Color.fromRGBO(255, 255, 255, 0.2),
                    label: ww.threshold.toStringAsFixed(1),
                    onChanged: (val) {
                      ww.setThreshold(val);
                      setInnerState(() {});
                    },
                  ),
                ),
                Text(
                  ww.threshold.toStringAsFixed(1),
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Cera Pro',
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text("Testing wake word detection for 5 seconds. Say 'hey rhasspy'..."),
                    backgroundColor: Color.fromRGBO(255, 87, 51, 1),
                    duration: Duration(seconds: 5),
                  ),
                );
                final maxScore = await WakeWordService.instance.runTest(durationSeconds: 5);
                messenger.hideCurrentSnackBar();
                if (maxScore < 0) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text("No audio received. Check microphone permission."),
                      backgroundColor: Colors.red,
                    ),
                  );
                } else if (maxScore < 0.3) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text("Max score: ${maxScore.toStringAsFixed(3)}. Try speaking louder or reducing sensitivity."),
                      backgroundColor: Colors.orange,
                    ),
                  );
                } else {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text("Max score: ${maxScore.toStringAsFixed(3)}. If this is above your threshold, detection should work!"),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
                setInnerState(() {});
              },
              icon: const Icon(Icons.science_outlined, size: 18),
              label: const Text("Test Wake Word"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromRGBO(255, 87, 51, 1),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildWebSearchToggle() {
    return StatefulBuilder(
      builder: (context, setInnerState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Web Search",
              style: TextStyle(
                color: Color.fromRGBO(255, 87, 51, 1),
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cera Pro',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              r"Appends :online to the model so OpenRouter runs a web search before answering. Costs extra credits even on free models (~$0.001/search on Exa, varies for native search models).",
              style: TextStyle(
                color: Color.fromRGBO(255, 138, 101, 0.8),
                fontSize: 14,
                fontFamily: 'Cera Pro',
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    "Web search on every request",
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Cera Pro',
                      fontSize: 14,
                    ),
                  ),
                ),
                FutureBuilder<bool>(
                  future: providers.getWebSearchEnabled(),
                  builder: (context, snapshot) {
                    final enabled = snapshot.data ?? false;
                    return Switch(
                      value: enabled,
                      onChanged: (val) async {
                        await providers.setWebSearchEnabled(val);
                        setInnerState(() {});
                      },
                      activeColor: const Color.fromRGBO(255, 87, 51, 1),
                    );
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildBraveSearchSection() {
    bool braveSaved = false;
    final keyController = TextEditingController();
    return StatefulBuilder(
      builder: (context, setInnerState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Brave Search",
              style: TextStyle(
                color: Color.fromRGBO(255, 87, 51, 1),
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cera Pro',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Uses Brave Search API to find relevant web results, then feeds them into whatever provider/model you have selected. Works with any provider. Get a free API key at api.search.brave.com.",
              style: TextStyle(
                color: Color.fromRGBO(255, 138, 101, 0.8),
                fontSize: 14,
                fontFamily: 'Cera Pro',
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    "Use Brave Search",
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Cera Pro',
                      fontSize: 14,
                    ),
                  ),
                ),
                FutureBuilder<bool>(
                  future: BraveSearchService.isEnabled(),
                  builder: (context, snapshot) {
                    final enabled = snapshot.data ?? false;
                    return Switch(
                      value: enabled,
                      onChanged: (val) async {
                        await BraveSearchService.setEnabled(val);
                        setInnerState(() {});
                      },
                      activeColor: const Color.fromRGBO(255, 87, 51, 1),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            FutureBuilder<String>(
              future: BraveSearchService.getApiKey(),
              builder: (context, snapshot) {
                final currentKey = snapshot.data ?? '';
                if (keyController.text.isEmpty && currentKey.isNotEmpty) {
                  keyController.text = currentKey;
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: keyController,
                      decoration: const InputDecoration(
                        labelText: "Brave Search API Key",
                        hintText: "Enter your Brave API key",
                        border: OutlineInputBorder(),
                        labelStyle: TextStyle(color: Colors.white70),
                        hintStyle: TextStyle(color: Colors.white38),
                      ),
                      style: const TextStyle(color: Colors.white),
                      obscureText: true,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: () async {
                            await BraveSearchService.setApiKey(keyController.text.trim());
                            setInnerState(() {
                              braveSaved = true;
                            });
                            Future.delayed(Duration(seconds: 2), () {
                              setInnerState(() {
                                braveSaved = false;
                              });
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color.fromRGBO(255, 87, 51, 1),
                            foregroundColor: Colors.white,
                          ),
                          child: Text(braveSaved ? "Saved!" : "Save Brave Key"),
                        ),
                        if (braveSaved) ...[
                          const SizedBox(width: 8),
                          const Text(
                            "Saved!",
                            style: TextStyle(
                              color: Colors.greenAccent,
                              fontFamily: 'Cera Pro',
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _modelTile(String id, String label, bool isSelected) {
    return InkWell(
      onTap: () {
        setState(() {
          _useCustomModel = false;
          _selectedModelId = id;
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

  Widget _buildTtsSection() {
    return InkWell(
      onTap: _showTtsSettingsDialog,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Text-to-Speech",
                  style: TextStyle(
                    color: Color.fromRGBO(255, 87, 51, 1),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cera Pro',
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  "Voice, engine, and speech rate settings.",
                  style: TextStyle(
                    color: Color.fromRGBO(255, 138, 101, 0.8),
                    fontSize: 14,
                    fontFamily: 'Cera Pro',
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            color: Color.fromRGBO(255, 87, 51, 1),
          ),
        ],
      ),
    );
  }

  void _showTtsSettingsDialog() async {
    final prefs = await SharedPreferences.getInstance();
    double speechRate = prefs.getDouble('tts_speech_rate') ?? 0.5;
    double pitch = prefs.getDouble('tts_pitch') ?? 1.0;
    String selectedEngine = prefs.getString('tts_engine') ?? '';
    String selectedLanguage = prefs.getString('tts_language') ?? '';
    String selectedVoiceName = prefs.getString('tts_voice_name') ?? '';
    const channel = MethodChannel('arya.tts');

    // Native-loaded state
    List<Map<String, String>> engines = [];
    List<Map<String, String>> voices = [];
    bool enginesLoading = true;
    bool voicesLoading = true;

    // Load engines from native side (returns maps with name+label)
    try {
      final result = await channel.invokeMethod('getEngines');
      if (result is List) {
        engines = (result as List).map((e) {
          if (e is Map) return Map<String, String>.from(e as Map);
          return <String, String>{};
        }).toList();
      }
    } catch (_) {}
    enginesLoading = false;

    // Pre-select default engine if none saved
    if (selectedEngine.isEmpty) {
      try {
        final defaultEngine = await channel.invokeMethod('getDefaultEngine');
        if (defaultEngine is String && defaultEngine.isNotEmpty) {
          selectedEngine = defaultEngine;
        }
      } catch (_) {}
    }

    // Load voices from native side (pure data fetch)
    Future<List<Map<String, String>>> loadVoices(String forEngine) async {
      try {
        final result = await channel.invokeMethod('getVoices', {'engine': forEngine});
        if (result is List) {
          return (result as List).map((v) {
            if (v is Map) return Map<String, String>.from(v as Map);
            return <String, String>{};
          }).toList();
        }
      } catch (_) {}
      return [];
    }

    // Initial voice load for saved or default engine
    if (selectedEngine.isNotEmpty) {
      voices = await loadVoices(selectedEngine);
      voicesLoading = false;
    } else {
      voicesLoading = false;
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredVoices = voices
                .where((v) =>
                    v['locale'] == selectedLanguage ||
                    selectedLanguage.isEmpty)
                .toList();

            return AlertDialog(
              backgroundColor: const Color.fromRGBO(30, 30, 30, 1),
              title: const Text(
                "Text-to-Speech Settings",
                style: TextStyle(
                  color: Color.fromRGBO(255, 87, 51, 1),
                  fontFamily: 'Cera Pro',
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Engine selector
                    const Text(
                      "Engine",
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'Cera Pro',
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (enginesLoading)
                      const Text(
                        "Loading...",
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      )
                    else if (engines.isEmpty)
                      const Text(
                        "No engines found.",
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      )
                    else
                      DropdownButton<String>(
                        isExpanded: true,
                        value: engines.any((e) => e['name'] == selectedEngine)
                            ? selectedEngine
                            : null,
                        dropdownColor: const Color.fromRGBO(30, 30, 30, 1),
                        hint: const Text(
                          "Select engine",
                          style: TextStyle(color: Colors.grey),
                        ),
                        items: engines.map((e) {
                          return DropdownMenuItem(
                            value: e['name'] ?? '',
                            child: Text(
                              e['label'] ?? e['name'] ?? '',
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'Cera Pro',
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (val) async {
                          if (val == null) return;
                          setDialogState(() {
                            selectedEngine = val;
                            selectedLanguage = '';
                            selectedVoiceName = '';
                            voicesLoading = true;
                            voices = [];
                          });
                          final newVoices = await loadVoices(val);
                          if (dialogContext.mounted) {
                            setDialogState(() {
                              voices = newVoices;
                              voicesLoading = false;
                              if (voices.isNotEmpty) {
                                selectedLanguage =
                                    voices.first['locale'] ?? '';
                                selectedVoiceName =
                                    voices.first['name'] ?? '';
                              }
                            });
                          }
                        },
                      ),
                    const SizedBox(height: 12),

                    // Language selector
                    if (selectedEngine.isNotEmpty) ...[
                      const Text(
                        "Language",
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'Cera Pro',
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (voicesLoading)
                        const Text(
                          "Loading...",
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        )
                      else if (voices.isEmpty)
                        const Text(
                          "No voices available.",
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        )
                      else
                        DropdownButton<String>(
                          isExpanded: true,
                          value: voices
                                  .map((v) => v['locale'] ?? '')
                                  .toSet()
                                  .contains(selectedLanguage)
                              ? selectedLanguage
                              : null,
                          dropdownColor:
                              const Color.fromRGBO(30, 30, 30, 1),
                          hint: const Text(
                            "Select language",
                            style: TextStyle(color: Colors.grey),
                          ),
                          items: voices
                              .map((v) => v['locale'] ?? '')
                              .toSet()
                              .map((locale) {
                            return DropdownMenuItem(
                              value: locale,
                              child: Text(
                                locale,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'Cera Pro',
                                  fontSize: 13,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val == null) return;
                            setDialogState(() {
                              selectedLanguage = val;
                              selectedVoiceName = '';
                            });
                            // Auto-select first voice for this locale
                            final match = voices.firstWhere(
                              (v) => v['locale'] == val,
                              orElse: () => <String, String>{},
                            );
                            if (match.isNotEmpty) {
                              setDialogState(() {
                                selectedVoiceName = match['name'] ?? '';
                              });
                            }
                          },
                        ),
                      const SizedBox(height: 12),
                    ],

                    // Voice selector
                    if (selectedLanguage.isNotEmpty) ...[
                      const Text(
                        "Voice",
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'Cera Pro',
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (voicesLoading)
                        const Text(
                          "Loading...",
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        )
                      else if (filteredVoices.isEmpty)
                        const Text(
                          "No voices for this language.",
                          style: TextStyle(
                              color: Colors.grey, fontSize: 13),
                        )
                      else
                        SizedBox(
                          height: 100,
                          child: ListView(
                            children: filteredVoices.map((voice) {
                              final name = voice['name'] ?? 'unknown';
                              return RadioListTile<String>(
                                title: Text(
                                  name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'Cera Pro',
                                    fontSize: 13,
                                  ),
                                ),
                                value: name,
                                groupValue: selectedVoiceName,
                                onChanged: (val) {
                                  setDialogState(() {
                                    if (val != null) selectedVoiceName = val;
                                  });
                                },
                                activeColor: const Color
                                    .fromRGBO(255, 87, 51, 1),
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                              );
                            }).toList(),
                          ),
                        ),
                      const SizedBox(height: 12),
                    ],

                    // Speech Rate
                    const Text(
                      "Speech Rate",
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'Cera Pro',
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    Slider(
                      value: speechRate,
                      min: 0.1,
                      max: 1.0,
                      divisions: 18,
                      activeColor: const Color.fromRGBO(255, 87, 51, 1),
                      inactiveColor:
                          const Color.fromRGBO(255, 87, 51, 0.3),
                      label: speechRate.toStringAsFixed(1),
                      onChanged: (val) {
                        setDialogState(() {
                          speechRate = val;
                        });
                      },
                    ),
                    const SizedBox(height: 8),

                    // Pitch
                    const Text(
                      "Pitch",
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'Cera Pro',
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    Slider(
                      value: pitch,
                      min: 0.5,
                      max: 2.0,
                      divisions: 15,
                      activeColor: const Color.fromRGBO(255, 87, 51, 1),
                      inactiveColor:
                          const Color.fromRGBO(255, 87, 51, 0.3),
                      label: pitch.toStringAsFixed(1),
                      onChanged: (val) {
                        setDialogState(() {
                          pitch = val;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Test button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          final testTts = FlutterTts();
                          if (selectedEngine.isNotEmpty) {
                            testTts.setEngine(selectedEngine);
                          }
                          if (selectedLanguage.isNotEmpty) {
                            testTts.setLanguage(selectedLanguage);
                          }
                          if (selectedVoiceName.isNotEmpty) {
                            final match = voices.firstWhere(
                              (v) => v['name'] == selectedVoiceName,
                              orElse: () => <String, String>{},
                            );
                            if (match.isNotEmpty) {
                              testTts.setVoice(
                                  Map<String, String>.from(match));
                            }
                          }
                          testTts.setSpeechRate(speechRate);
                          testTts.setPitch(pitch);
                          testTts.speak(
                              "Hello. I am ARYA. This is my voice.");
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              const Color.fromRGBO(255, 87, 51, 1),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          "Test Voice",
                          style: TextStyle(fontFamily: 'Cera Pro'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(
                      color: Colors.grey,
                      fontFamily: 'Cera Pro',
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('tts_configured', true);
                    await prefs.setString('tts_engine', selectedEngine);
                    await prefs.setString(
                        'tts_language', selectedLanguage);
                    await prefs.setString(
                        'tts_voice_name', selectedVoiceName);
                    await prefs.setDouble(
                        'tts_speech_rate', speechRate);
                    await prefs.setDouble('tts_pitch', pitch);
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromRGBO(255, 87, 51, 1),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    "Save",
                    style: TextStyle(fontFamily: 'Cera Pro'),
                  ),
                ),
              ],
            );
          },
        );
      },
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
            _buildProviderSelector(),
            _buildApiKeyField(),
            _buildCustomBaseUrlField(),
            _buildSaveButton(),
            const SizedBox(height: 32),
            _buildSystemPromptSection(),
            const SizedBox(height: 32),
            const Divider(color: Color.fromRGBO(255, 87, 51, 0.3)),
            const SizedBox(height: 16),
            _buildModelSection(),
            const SizedBox(height: 32),
            const Divider(color: Color.fromRGBO(255, 87, 51, 0.3)),
            const SizedBox(height: 16),
            _buildModelRoutingSection(),
            const SizedBox(height: 32),
            const Divider(color: Color.fromRGBO(255, 87, 51, 0.3)),
            const SizedBox(height: 16),
            _buildTtsSection(),
            const SizedBox(height: 32),
            const Divider(color: Color.fromRGBO(255, 87, 51, 0.3)),
            const SizedBox(height: 16),
            _buildWebSearchToggle(),
            const SizedBox(height: 32),
            _buildBraveSearchSection(),
            const SizedBox(height: 32),
            const Divider(color: Color.fromRGBO(255, 87, 51, 0.3)),
            const SizedBox(height: 16),
            _buildMemorySection(),
            const SizedBox(height: 32),
            const Divider(color: Color.fromRGBO(255, 87, 51, 0.3)),
            const SizedBox(height: 16),
            const Text(
              "Background Service",
              style: TextStyle(
                color: Color.fromRGBO(255, 87, 51, 1),
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cera Pro',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Keeps ARYA running when the screen is locked. 'Start Mic' notification lets RemoteFix trigger voice input.",
              style: TextStyle(
                color: Color.fromRGBO(255, 138, 101, 0.8),
                fontSize: 14,
                fontFamily: 'Cera Pro',
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    BackgroundService.isRunning
                        ? "Service is running"
                        : "Service is stopped",
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Cera Pro',
                      fontSize: 14,
                    ),
                  ),
                ),
                Switch(
                  value: BackgroundService.isRunning,
                  onChanged: (val) async {
                    await BackgroundService.setEnabled(val);
                    setState(() {});
                  },
                  activeColor: const Color.fromRGBO(255, 87, 51, 1),
                ),
              ],
            ),
            const SizedBox(height: 32),
            const Divider(color: Color.fromRGBO(255, 87, 51, 0.3)),
            const SizedBox(height: 16),
            const Text(
              "Mic Announcement",
              style: TextStyle(
                color: Color.fromRGBO(255, 87, 51, 1),
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cera Pro',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "What ARYA says when the microphone starts listening.",
              style: TextStyle(
                color: Color.fromRGBO(255, 138, 101, 0.8),
                fontSize: 14,
                fontFamily: 'Cera Pro',
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            _announceRadio(
              value: 0,
              title: "Silent",
              subtitle: "No announcement",
              groupValue: _announceMode,
              onChanged: (v) async {
                if (v == null) return;
                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt('mic_announcement_mode', v);
                if (mounted) setState(() => _announceMode = v);
              },
            ),
            _announceRadio(
              value: 1,
              title: "Say 'Listening'",
              subtitle: "Short verbal cue",
              groupValue: _announceMode,
              onChanged: (v) async {
                if (v == null) return;
                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt('mic_announcement_mode', v);
                if (mounted) setState(() => _announceMode = v);
              },
            ),
            _announceRadio(
              value: 2,
              title: "Provider + Model",
              subtitle: "e.g. 'OpenRouter, GPT Mini' plus Brave status",
              groupValue: _announceMode,
              onChanged: (v) async {
                if (v == null) return;
                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt('mic_announcement_mode', v);
                if (mounted) setState(() => _announceMode = v);
              },
            ),
            const SizedBox(height: 24),
            const Text(
              "Listening Duration",
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontFamily: 'Cera Pro',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Max time mic stays open: ${_listeningDuration}s",
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
                fontFamily: 'Cera Pro',
              ),
            ),
            Slider(
              value: _listeningDuration.toDouble(),
              min: 5,
              max: 120,
              divisions: 23,
              activeColor: const Color.fromRGBO(255, 87, 51, 1),
              inactiveColor: const Color.fromRGBO(255, 87, 51, 0.3),
              label: "${_listeningDuration}s",
              onChanged: (v) async {
                final val = v.round();
                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt('listening_duration_seconds', val);
                if (mounted) setState(() => _listeningDuration = val);
              },
            ),
            const SizedBox(height: 16),
            const Text(
              "Pause Duration",
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontFamily: 'Cera Pro',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Silence before auto-stop: ${_pauseDuration}s",
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
                fontFamily: 'Cera Pro',
              ),
            ),
            Slider(
              value: _pauseDuration.toDouble(),
              min: 1,
              max: 30,
              divisions: 29,
              activeColor: const Color.fromRGBO(255, 87, 51, 1),
              inactiveColor: const Color.fromRGBO(255, 87, 51, 0.3),
              label: "${_pauseDuration}s",
              onChanged: (v) async {
                final val = v.round();
                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt('pause_duration_seconds', val);
                if (mounted) setState(() => _pauseDuration = val);
              },
            ),
            const SizedBox(height: 32),
            const Divider(color: Color.fromRGBO(255, 87, 51, 0.3)),
            const SizedBox(height: 16),
            _buildWakeWordSection(),
            const SizedBox(height: 32),
            const Divider(color: Color.fromRGBO(255, 87, 51, 0.3)),
            const SizedBox(height: 16),
            _buildSettingsBackupSection(),
            const SizedBox(height: 32),
            const Divider(color: Color.fromRGBO(255, 87, 51, 0.3)),
            const SizedBox(height: 16),
            const Text(
              "Debug Logging",
              style: TextStyle(
                color: Color.fromRGBO(255, 87, 51, 1),
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cera Pro',
              ),
            ),
            const SizedBox(height: 8),
            StatefulBuilder(
              builder: (context, setInnerState) {
                final logger = DebugLogger();
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            "Verbose logging (more detail in log)",
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'Cera Pro',
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Switch(
                          value: logger.verboseEnabled,
                          onChanged: (val) {
                            logger.setVerboseEnabled(val);
                            setInnerState(() {});
                          },
                          activeColor: const Color.fromRGBO(255, 87, 51, 1),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: () => _shareLog(context),
                        icon: const Icon(
                          Icons.bug_report,
                          color: Color.fromRGBO(255, 87, 51, 1),
                        ),
                        label: const Text(
                          "Share Log",
                          style: TextStyle(
                            color: Color.fromRGBO(255, 87, 51, 1),
                            fontFamily: 'Cera Pro',
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: const Color.fromRGBO(255, 87, 51, 1).withValues(alpha: 0.5),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 32),
            const Divider(color: Color.fromRGBO(255, 87, 51, 0.3)),
            const SizedBox(height: 16),
            const Text(
              "Save Location",
              style: TextStyle(
                color: Color.fromRGBO(255, 87, 51, 1),
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cera Pro',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Choose where conversation files are saved. Defaults to app documents folder.",
              style: TextStyle(
                color: Color.fromRGBO(255, 138, 101, 0.8),
                fontSize: 14,
                fontFamily: 'Cera Pro',
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _pickFolder,
                icon: const Icon(
                  Icons.folder_open,
                  color: Color.fromRGBO(255, 87, 51, 1),
                ),
                label: const Text(
                  "Pick Folder",
                  style: TextStyle(
                    color: Color.fromRGBO(255, 87, 51, 1),
                    fontFamily: 'Cera Pro',
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: const Color.fromRGBO(255, 87, 51, 1).withValues(alpha: 0.5),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFolder() async {
    final uri = await SaveDirectoryPicker.pickDirectory();
    if (uri != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save folder set. Files will be saved there.'),
          backgroundColor: Colors.green,
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Folder picking cancelled or failed.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Widget _announceRadio({
    required int value,
    required String title,
    required String subtitle,
    required int groupValue,
    required ValueChanged<int?> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            Radio<int>(
              value: value,
              groupValue: groupValue,
              onChanged: onChanged,
              activeColor: const Color.fromRGBO(255, 87, 51, 1),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Cera Pro',
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
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
}
