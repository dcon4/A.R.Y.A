import 'dart:io';
import 'package:arya/services/api_providers.dart' as providers;
import 'package:arya/services/brave_search_service.dart';
import 'package:arya/services/background_service.dart';
import 'package:arya/services/debug_logger.dart';
import 'package:arya/services/openai_service.dart';
import 'package:arya/services/save_directory_picker.dart';
import 'package:arya/services/wake_word_service.dart';
import 'package:arya/widgets/model_selector.dart';
import 'package:flutter/material.dart';
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
  bool _isSaved = false;
  bool _obscureKey = true;
  String _selectedProviderId = 'openrouter';
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

    setState(() {
      _selectedProviderId = savedProviderId;
      _apiKeyController.text = savedKey;
      _selectedModelId = isCustomModel ? provider.defaultModel : savedModel;
      _useCustomModel = isCustomModel;
      _customModelController.text = isCustomModel ? savedModel : '';
      _customBaseUrlController.text = savedCustomBaseUrl;
      _currentModels = provider.models;
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
                      ww.stop();
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
          ],
        );
      },
    );
  }

  Widget _buildBluetoothSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        const Divider(color: Color.fromRGBO(255, 87, 51, 0.3)),
        const SizedBox(height: 16),
        const Text(
          "Bluetooth Mic Control",
          style: TextStyle(
            color: Color.fromRGBO(255, 87, 51, 1),
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'Cera Pro',
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "Press the play/pause button on your Bluetooth headset to start or stop the microphone.",
          style: TextStyle(
            color: Color.fromRGBO(255, 138, 101, 0.8),
            fontSize: 14,
            fontFamily: 'Cera Pro',
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        StatefulBuilder(
          builder: (context, setInnerState) {
            return FutureBuilder<bool>(
              future: BackgroundService.getBluetoothEnabled(),
              builder: (context, snapshot) {
                final enabled = snapshot.data ?? false;
                return Row(
                  children: [
                    const Expanded(
                      child: Text(
                        "Bluetooth headset button control",
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'Cera Pro',
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Switch(
                      value: enabled,
                      onChanged: (val) async {
                        await BackgroundService.setBluetoothEnabled(val);
                        setInnerState(() {});
                      },
                      activeColor: const Color.fromRGBO(255, 87, 51, 1),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ],
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
            _buildModelSection(),
            const SizedBox(height: 32),
            const Divider(color: Color.fromRGBO(255, 87, 51, 0.3)),
            const SizedBox(height: 16),
            _buildWebSearchToggle(),
            const SizedBox(height: 32),
            _buildBraveSearchSection(),
            const SizedBox(height: 32),
            const Divider(color: Color.fromRGBO(255, 87, 51, 0.3)),
            const SizedBox(height: 16),
            _buildWakeWordSection(),
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
            _buildBluetoothSection(),
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
}
