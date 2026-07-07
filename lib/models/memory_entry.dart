class MemoryEntry {
  final String id;
  final String type;
  final String content;
  final DateTime timestamp;
  int hitCount;
  bool isPromoted;
  List<String> keywords;

  MemoryEntry({
    required this.id,
    required this.type,
    required this.content,
    required this.timestamp,
    this.hitCount = 0,
    this.isPromoted = false,
    List<String>? keywords,
  }) : keywords = keywords ?? _extractKeywords(content);

  MemoryEntry.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        type = json['type'] as String,
        content = json['content'] as String,
        timestamp = DateTime.parse(json['timestamp'] as String),
        hitCount = json['hitCount'] as int? ?? 0,
        isPromoted = json['isPromoted'] as bool? ?? false,
        keywords = (json['keywords'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            _extractKeywords(json['content'] as String);

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'hitCount': hitCount,
        'isPromoted': isPromoted,
        'keywords': keywords,
      };

  static const _stopWords = {
    'a', 'an', 'the', 'is', 'are', 'was', 'were', 'be', 'been',
    'being', 'have', 'has', 'had', 'do', 'does', 'did', 'will',
    'would', 'could', 'should', 'may', 'might', 'can', 'shall',
    'to', 'of', 'in', 'for', 'on', 'with', 'at', 'by', 'from',
    'as', 'into', 'through', 'during', 'before', 'after', 'above',
    'below', 'between', 'out', 'off', 'over', 'under', 'again',
    'further', 'then', 'once', 'here', 'there', 'when', 'where',
    'why', 'how', 'all', 'each', 'every', 'both', 'few', 'more',
    'most', 'other', 'some', 'such', 'no', 'nor', 'not', 'only',
    'own', 'same', 'so', 'than', 'too', 'very', 'just', 'because',
    'and', 'but', 'or', 'if', 'while', 'that', 'this', 'these',
    'those', 'it', 'its', 'i', 'me', 'my', 'you', 'your', 'he',
    'she', 'we', 'they', 'what', 'which', 'who', 'about', 'up',
    'like', 'also', 'get', 'got', 'make', 'made', 'know', 'think',
  };

  static List<String> _extractKeywords(String text) {
    final lower = text.toLowerCase();
    final words = lower.split(RegExp(r'[^\w]+'));
    return words.where((w) => w.length > 2 && !_stopWords.contains(w)).toSet().toList();
  }

  int scoreAgainst(String query) {
    final queryWords = _extractKeywords(query);
    if (queryWords.isEmpty) return 0;
    int score = 0;
    for (final kw in queryWords) {
      if (keywords.contains(kw)) score += 2;
      if (content.toLowerCase().contains(kw)) score += 1;
    }
    return score;
  }
}
