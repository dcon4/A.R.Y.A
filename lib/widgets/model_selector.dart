import 'package:arya/services/api_providers.dart' as providers;
import 'package:arya/services/debug_logger.dart';
import 'package:arya/services/model_fetcher_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ModelSelector extends StatefulWidget {
  final String providerId;
  final String apiKey;
  final String selectedModelId;
  final ValueChanged<String> onModelSelected;
  final VoidCallback? onRefresh;

  const ModelSelector({
    super.key,
    required this.providerId,
    required this.apiKey,
    required this.selectedModelId,
    required this.onModelSelected,
    this.onRefresh,
  });

  @override
  State<ModelSelector> createState() => _ModelSelectorState();
}

class _ModelSelectorState extends State<ModelSelector> {
  final _logger = DebugLogger();
  final _fetcher = ModelFetcherService();
  
  List<Map<String, dynamic>> _allModels = [];
  List<Map<String, dynamic>> _filteredModels = [];
  bool _isLoading = false;
  bool _showFreeOnly = true;
  bool _showWebSearchOnly = false;
  String _searchQuery = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSavedPreferences();
    _fetchModels();
  }

  Future<void> _loadSavedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _showFreeOnly = prefs.getBool('filter_free_models_only') ?? true;
      _showWebSearchOnly = prefs.getBool('filter_web_search_only') ?? false;
    });
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('filter_free_models_only', _showFreeOnly);
    await prefs.setBool('filter_web_search_only', _showWebSearchOnly);
  }

  Future<void> _fetchModels() async {
    if (widget.apiKey.isEmpty) {
      setState(() {
        _error = 'API key is required to fetch models';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      List<Map<String, dynamic>> models = [];

      switch (widget.providerId) {
        case 'openrouter':
          models = await _fetcher.fetchOpenRouterModels(widget.apiKey);
          break;
        case 'openai':
          models = await _fetcher.fetchOpenAIModels(widget.apiKey);
          break;
        case 'groq':
          models = await _fetcher.fetchGroqModels(widget.apiKey);
          break;
        case 'deepseek':
          models = await _fetcher.fetchDeepSeekModels(widget.apiKey);
          break;
        default:
          _error = 'Unknown provider: ${widget.providerId}';
      }

      if (models.isEmpty && _error == null) {
        _error = 'No models available. Check your API key.';
      }

      setState(() {
        _allModels = _fetcher.sortModels(models);
        _applyFilters();
        _isLoading = false;
      });

      _logger.log('ModelSelector', 'Fetched ${models.length} models for ${widget.providerId}');
    } catch (e) {
      _logger.error('ModelSelector', 'Failed to fetch models', e);
      setState(() {
        _error = 'Failed to fetch models: $e';
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    _filteredModels = _fetcher.filterModels(
      models: _allModels,
      freeOnly: _showFreeOnly,
      webSearchOnly: _showWebSearchOnly,
      searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
    );
  }

  void _toggleFreeFilter() {
    setState(() {
      _showFreeOnly = !_showFreeOnly;
      _applyFilters();
    });
    _savePreferences();
  }

  void _toggleWebSearchFilter() {
    setState(() {
      _showWebSearchOnly = !_showWebSearchOnly;
      _applyFilters();
    });
    _savePreferences();
  }

  void _updateSearch(String query) {
    setState(() {
      _searchQuery = query;
      _applyFilters();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with refresh button
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Available Models',
              style: TextStyle(
                color: Color.fromRGBO(255, 87, 51, 1),
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cera Pro',
              ),
            ),
            if (!_isLoading)
              IconButton(
                icon: const Icon(
                  Icons.refresh,
                  color: Color.fromRGBO(255, 87, 51, 1),
                  size: 20,
                ),
                onPressed: _fetchModels,
                tooltip: 'Refresh models',
              ),
          ],
        ),
        const SizedBox(height: 8),

        // Search field
        TextField(
          onChanged: _updateSearch,
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'Cera Pro',
            fontSize: 14,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color.fromRGBO(255, 255, 255, 0.08),
            hintText: 'Search models...',
            hintStyle: TextStyle(
              color: Colors.grey[600],
              fontFamily: 'Cera Pro',
            ),
            prefixIcon: const Icon(
              Icons.search,
              color: Color.fromRGBO(255, 87, 51, 0.7),
              size: 20,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color.fromRGBO(255, 87, 51, 0.5),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: const Color.fromRGBO(255, 87, 51, 1).withValues(alpha: 0.3),
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Filter toggles
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color.fromRGBO(255, 87, 51, 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color.fromRGBO(255, 87, 51, 0.2),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [\n                  Expanded(\n                    child: Column(\n                      crossAxisAlignment: CrossAxisAlignment.start,\n                      children: [\n                        const Text(\n                          'Free Models Only',\n                          style: TextStyle(\n                            color: Colors.white,\n                            fontFamily: 'Cera Pro',\n                            fontSize: 12,\n                            fontWeight: FontWeight.bold,\n                          ),\n                        ),\n                        Text(\n                          '${_filteredModels.length} available',\n                          style: TextStyle(\n                            color: Colors.grey[500],\n                            fontFamily: 'Cera Pro',\n                            fontSize: 10,\n                          ),\n                        ),\n                      ],\n                    ),\n                  ),\n                  Switch(\n                    value: _showFreeOnly,\n                    onChanged: (_) => _toggleFreeFilter(),\n                    activeColor: const Color.fromRGBO(255, 87, 51, 1),\n                  ),\n                ],\n              ),\n              const Divider(\n                color: Color.fromRGBO(255, 87, 51, 0.2),\n                height: 12,\n              ),\n              Row(\n                children: [\n                  Expanded(\n                    child: Column(\n                      crossAxisAlignment: CrossAxisAlignment.start,\n                      children: [\n                        const Text(\n                          'Web Search Capable',\n                          style: TextStyle(\n                            color: Colors.white,\n                            fontFamily: 'Cera Pro',\n                            fontSize: 12,\n                            fontWeight: FontWeight.bold,\n                          ),\n                        ),\n                        Text(\n                          'Models that support :online suffix',\n                          style: TextStyle(\n                            color: Colors.grey[500],\n                            fontFamily: 'Cera Pro',\n                            fontSize: 10,\n                          ),\n                        ),\n                      ],\n                    ),\n                  ),\n                  Switch(\n                    value: _showWebSearchOnly,\n                    onChanged: (_) => _toggleWebSearchFilter(),\n                    activeColor: const Color.fromRGBO(255, 87, 51, 1),\n                  ),\n                ],\n              ),\n            ],\n          ),\n        ),
        const SizedBox(height: 12),

        // Loading state
        if (_isLoading)
n          const Padding(\n            padding: EdgeInsets.symmetric(vertical: 20),\n            child: Center(\n              child: CircularProgressIndicator(\n                valueColor: AlwaysStoppedAnimation<Color>(\n                  Color.fromRGBO(255, 87, 51, 1),\n                ),\n              ),\n            ),\n          ),

        // Error state
        if (_error != null)
          Container(\n            padding: const EdgeInsets.all(12),\n            decoration: BoxDecoration(\n              color: Colors.red.withValues(alpha: 0.1),\n              borderRadius: BorderRadius.circular(12),\n              border: Border.all(\n                color: Colors.red.withValues(alpha: 0.3),\n              ),\n            ),\n            child: Text(\n              _error!,\n              style: const TextStyle(\n                color: Colors.redAccent,\n                fontFamily: 'Cera Pro',\n                fontSize: 12,\n              ),\n            ),\n          ),

        // Models list
        if (!_isLoading && _error == null)
          if (_filteredModels.isEmpty)\n            Container(\n              padding: const EdgeInsets.all(16),\n              decoration: BoxDecoration(\n                color: const Color.fromRGBO(255, 255, 255, 0.05),\n                borderRadius: BorderRadius.circular(12),\n                border: Border.all(\n                  color: const Color.fromRGBO(255, 87, 51, 0.2),\n                ),\n              ),\n              child: const Text(\n                'No models match your filters',\n                style: TextStyle(\n                  color: Colors.grey,\n                  fontFamily: 'Cera Pro',\n                  fontSize: 12,\n                  fontStyle: FontStyle.italic,\n                ),\n              ),\n            )\n          else\n            ConstrainedBox(\n              constraints: const BoxConstraints(maxHeight: 300),\n              child: ListView.builder(\n                shrinkWrap: true,\n                itemCount: _filteredModels.length,\n                itemBuilder: (context, index) {\n                  final model = _filteredModels[index];\n                  final isSelected =\n                      widget.selectedModelId == model['id'];\n                  return InkWell(\n                    onTap: () {\n                      widget.onModelSelected(model['id']);\n                    },\n                    child: Container(\n                      margin: const EdgeInsets.only(bottom: 8),\n                      padding: const EdgeInsets.all(12),\n                      decoration: BoxDecoration(\n                        color: isSelected\n                            ? const Color.fromRGBO(255, 87, 51, 0.2)\n                            : const Color.fromRGBO(255, 255, 255, 0.05),\n                        borderRadius: BorderRadius.circular(12),\n                        border: Border.all(\n                          color: isSelected\n                              ? const Color.fromRGBO(255, 87, 51, 1)\n                              : const Color.fromRGBO(255, 87, 51, 0.2),\n                          width: isSelected ? 2 : 1,\n                        ),\n                      ),\n                      child: Row(\n                        children: [\n                          Icon(\n                            isSelected\n                                ? Icons.radio_button_checked\n                                : Icons.radio_button_off,\n                            color: const Color.fromRGBO(255, 87, 51, 1),\n                            size: 18,\n                          ),\n                          const SizedBox(width: 12),\n                          Expanded(\n                            child: Column(\n                              crossAxisAlignment:\n                                  CrossAxisAlignment.start,\n                              children: [\n                                Text(\n                                  model['name'] ?? model['id'],\n                                  style: const TextStyle(\n                                    color: Colors.white,\n                                    fontFamily: 'Cera Pro',\n                                    fontSize: 12,\n                                    fontWeight: FontWeight.bold,\n                                  ),\n                                  maxLines: 1,\n                                  overflow: TextOverflow.ellipsis,\n                                ),\n                                Text(\n                                  model['id'],\n                                  style: TextStyle(\n                                    color: Colors.grey[500],\n                                    fontFamily: 'Cera Pro',\n                                    fontSize: 10,\n                                  ),\n                                  maxLines: 1,\n                                  overflow: TextOverflow.ellipsis,\n                                ),\n                              ],\n                            ),\n                          ),\n                          if (model['is_free'] == true)\n                            Container(\n                              padding: const EdgeInsets.symmetric(\n                                horizontal: 8,\n                                vertical: 4,\n                              ),\n                              decoration: BoxDecoration(\n                                color: Colors.green.withValues(alpha: 0.2),\n                                borderRadius: BorderRadius.circular(6),\n                                border: Border.all(\n                                  color: Colors.green.withValues(alpha: 0.5),\n                                ),\n                              ),\n                              child: const Text(\n                                'FREE',\n                                style: TextStyle(\n                                  color: Colors.greenAccent,\n                                  fontFamily: 'Cera Pro',\n                                  fontSize: 9,\n                                  fontWeight: FontWeight.bold,\n                                ),\n                              ),\n                            ),\n                        ],\n                      ),\n                    ),\n                  );\n                },\n              ),\n            ),\n      ],\n    );\n  }\n}\n", "path": "lib/widgets/model_selector.dart", "repo": "A.R.Y.A"}