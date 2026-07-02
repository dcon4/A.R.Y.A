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
  bool _isSaved = false;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final savedKey = prefs.getString('openrouter_api_key') ?? '';
    setState(() {
      _apiKeyController.text = savedKey;
    });
  }

  Future<void> _saveApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('openrouter_api_key', _apiKeyController.text.trim());
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
    super.dispose();
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
      body: Padding(
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
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _saveApiKey,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromRGBO(255, 87, 51, 1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  _isSaved ? "Saved!" : "Save API Key",
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
                      "API key saved. ARYA is ready to use.",
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
