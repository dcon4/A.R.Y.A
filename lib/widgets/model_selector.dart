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
  bool _showFreeOnly = false;
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
      _showFreeOnly = prefs.getBool('filter_free_models_only') ?? false;
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
        _error = 'Enter an API key to fetch available models';
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
        case 'cerebras':
          models = await _fetcher.fetchCerebrasModels(widget.apiKey);
          break;
        default:
          _error = 'Model fetching not supported for this provider';
      }

      if (models.isEmpty && _error == null) {
        _error = 'No models found. Check your API key.';
      }

      setState(() {
        _allModels = _fetcher.sortModels(models);
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      _logger.error('ModelSelector', 'Failed to fetch models', e);
      setState(() {
        _error = 'Failed to fetch models';
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
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Free Models Only',
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'Cera Pro',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${_filteredModels.length} available',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontFamily: 'Cera Pro',
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _showFreeOnly,
                    onChanged: (_) => _toggleFreeFilter(),
                    activeColor: const Color.fromRGBO(255, 87, 51, 1),
                  ),
                ],
              ),
              const Divider(
                color: Color.fromRGBO(255, 87, 51, 0.2),
                height: 12,
              ),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Web Search Capable',
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'Cera Pro',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${_filteredModels.length} available',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontFamily: 'Cera Pro',
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _showWebSearchOnly,
                    onChanged: (_) => _toggleWebSearchFilter(),
                    activeColor: const Color.fromRGBO(255, 87, 51, 1),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  Color.fromRGBO(255, 87, 51, 1),
                ),
              ),
            ),
          ),
        if (_error != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.red.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              _error!,
              style: const TextStyle(
                color: Colors.redAccent,
                fontFamily: 'Cera Pro',
                fontSize: 12,
              ),
            ),
          ),
        if (!_isLoading && _error == null)
          if (_filteredModels.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color.fromRGBO(255, 255, 255, 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color.fromRGBO(255, 87, 51, 0.2),
                ),
              ),
              child: const Text(
                'No models match your filters',
                style: TextStyle(
                  color: Colors.grey,
                  fontFamily: 'Cera Pro',
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _filteredModels.length,
                itemBuilder: (context, index) {
                  final model = _filteredModels[index];
                  final isSelected = widget.selectedModelId == model['id'];
                  final isFree = model['is_free'] == true;
                  final supportsVision = model['supports_vision'] == true;
                  return InkWell(
                    onTap: () {
                      widget.onModelSelected(model['id']);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color.fromRGBO(255, 87, 51, 0.2)
                            : const Color.fromRGBO(255, 255, 255, 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? const Color.fromRGBO(255, 87, 51, 1)
                              : const Color.fromRGBO(255, 255, 255, 0.1),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: const Color.fromRGBO(255, 87, 51, 1),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  model['name'] ?? 'Unknown',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'Cera Pro',
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  model['id'] ?? '',
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontFamily: 'Cera Pro',
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isFree)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.green.withValues(alpha: 0.5),
                                ),
                              ),
                              child: const Text(
                                'FREE',
                                style: TextStyle(
                                  color: Colors.greenAccent,
                                  fontFamily: 'Cera Pro',
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          if (supportsVision)
                            const SizedBox(width: 6),
                          if (supportsVision)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color.fromRGBO(255, 87, 51, 0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color.fromRGBO(255, 87, 51, 0.5),
                                ),
                              ),
                              child: const Text(
                                'VISION',
                                style: TextStyle(
                                  color: Color.fromRGBO(255, 87, 51, 1),
                                  fontFamily: 'Cera Pro',
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
      ],
    );
  }
}
