import 'package:shared_preferences/shared_preferences.dart';

/// Enhanced query classifier for Smart Free mode.
///
/// Analyses a user query and returns a [QueryClassification] that describes
/// the intent, complexity, and whether ARYA should confirm before answering.
class QueryClassification {
  final String category;
  final bool isResearch;
  final bool isComplex;
  final double confidence;
  final bool needsConfirmation;
  final List<String> detectedTopics;
  final String? providerHint;
  final String? modelHint;

  const QueryClassification({
    required this.category,
    this.isResearch = false,
    this.isComplex = false,
    this.confidence = 1.0,
    this.needsConfirmation = false,
    this.detectedTopics = const [],
    this.providerHint,
    this.modelHint,
  });
}

class QueryClassifier {
  static final QueryClassifier instance = QueryClassifier._();
  QueryClassifier._();

  // --- Research signals ---

  static final _researchExactPhrases = RegExp(
    r'compared? to|versus|vs\.?|on the other hand|dissenting|'
    r'critics (?:argue|say|claim|believe|contend)|'
    r'mainstream (?:view|opinion|consensus|thinking)|'
    r'accepted (?:view|thinking|consensus)|'
    r'what do (?:you |the )?(?:experts|scientists|researchers|scholars) think|'
    r'what are (?:the |some )(?:arguments?|perspectives?|viewpoints?|opinions?)|'
    r'counter-?argument|alternative (?:view|explanation|theory|perspective)|'
    r'what does (?:the |recent )?(?:evidence|research|data|literature) say|'
    r'is there (?:evidence|proof|data|consensus)|'
    r'what (?:are|is) the (?:pros|cons|trade-?offs?|downsides?|benefits?|risks?)|'
    r'how (?:reliable|credible|accurate|valid|robust) is|'
    r'what (?:are )?the (?:different|various|competing) (?:schools?|theories?|approaches?|models?)|'
    r'contrarian|minority (?:view|opinion|position)|dissenting (?:view|opinion)',
  );

  static final _researchPatterns = [
    RegExp(r'\b(analyz|analys)\w*\b'),
    RegExp(r'\b(evaluat)\w*\b'),
    RegExp(r'\b(research|scholarly|academic)\b'),
    RegExp(r'\b(evidence|study|studies|data)\b.*\b(suggest|show|indicate|reveal|support)\b'),
    RegExp(r'\b(bias|biases|confirmation bias|cognitive bias)\b'),
    RegExp(r'\b(meta-?analysis|systematic review|literature review)\b'),
    RegExp(r'\b(what (?:is|are) the (?:latest|current|recent) (?:findings|discoveries|research|studies))\b'),
    RegExp(r'\bwhat (?:is|are) the (?:status quo|consensus|established|orthodox)\b'),
    RegExp(r'\bwhat (?:is|are) (?:the )?(?:alternatives?|other approaches?|different views?)\b'),
  ];

  // --- Complexity signals ---

  static final _complexityPatterns = [
    RegExp(r'\b(compare|contrast|differ|versus|vs\.?|trade-?off|pros?.?cons?)\b'),
    RegExp(r'\b(step[- ]by[- ]step|walk me through|explain in detail)\b'),
    RegExp(r'\b(why|how) (?:does|do|did|would|should|could|might|can)\b'),
    RegExp(r'\b(implications?|consequences?|ramifications?|effects?)\b'),
    RegExp(r'\b(multi[- ]part|several questions?|also|additionally|furthermore)\b'),
    RegExp(r'\b(history of|background of|context of|origin of)\b'),
    RegExp(r'\b(tell me about|describe|explain)\b.*\b(and|also|as well as|plus)\b'),
  ];

  // --- Topic detection ---

  static final _topicPatterns = {
    'science': RegExp(r'\b(science|scientific|physics|chemistry|biology|lab(?:oratory)?|experiment|hypothesis|theory|quantum|neuro|genetic|dna|rna|evolution|climate|astro(?:nomy|physics))\b'),
    'technology': RegExp(r'\b(tech(?:nology)?|comput(?:er|ing)|software|hardware|ai|artificial intelligence|machine learning|neural|programming|code|algorithm|database|cloud|cyber|blockchain|crypto|robot))\b'),
    'medicine': RegExp(r'\b(med(?:ical|icine|ication)|health|disease|symptom|diagnos|treatment|therap|surgery|vaccine|clinical|patient|doctor|pharmaceutical|drug)\b'),
    'politics': RegExp(r'\b(politic|government|policy|election|democrat|republican|congress|parliament|legislat|regulat|vote|campaign|partisan|ideolog))\b'),
    'economics': RegExp(r'\b(econom|financ|market|trade|gdp|inflation|recession|invest(?:ment|ing)|stock|bond|fiscal|monetary|budget|tax(?:ation)?)\b'),
    'philosophy': RegExp(r'\b(philosoph|moral|ethic|consciousness|existential|epistemolog|metaphysic|ontology|logic|reasoning|argument)\b'),
    'history': RegExp(r'\b(histor|ancient|medieval|century|war|revolution|empire|dynasty|civiliz|colonial|industrial)\b'),
    'law': RegExp(r'\b(law|legal|court|judge|attorney|statute|regulation|constitutional|litigation|rights|liability|tort)\b'),
  };

  // --- Category classification ---

  static final _codingPatterns = RegExp(
    r'\b(code|function|bug|debug|python|javascript|dart|java|swift|typescript'
    r'|implement|algorithm|error|fix|compile|syntax|api|class|method|variable'
    r'|program|develop|deploy|refactor|test|unit test|integration|git|docker|sql'
    r'|react|angular|flutter|android|ios|backend|frontend|full[- ]?stack)\b',
  );

  static final _quickPatterns = RegExp(
    r'\b(what is|who is|when|where|how many|how much|define|weather'
    r'|time|date|temperature|capital|population|meaning|synonym|'
    r'convert|calculate|how old|how far|how long|how tall|how fast)\b',
  );

  static final _creativePatterns = RegExp(
    r'\b(write|story|poem|describe|create|imagine|tell me about'
    r'|suggest|idea|draft|compose|generate|essay|letter|email'
    r'|brainstorm|fiction|narrative|prose|script|song)\b',
  );

  /// Classify a user query.
  ///
  /// When [smartFreeEnabled] is false, falls back to the original regex-based
  /// routing categories. When true, performs full analysis including research
  /// detection, complexity scoring, and confidence estimation.
  Future<QueryClassification> classify(
    String query, {
    bool smartFreeEnabled = false,
  }) async {
    final lower = query.toLowerCase().trim();

    if (!smartFreeEnabled) {
      return _simpleClassify(lower);
    }

    return _fullClassify(lower, query);
  }

  QueryClassification _simpleClassify(String lower) {
    if (_codingPatterns.hasMatch(lower)) {
      return const QueryClassification(category: 'coding');
    }
    if (_quickPatterns.hasMatch(lower)) {
      return const QueryClassification(category: 'quick');
    }
    if (_creativePatterns.hasMatch(lower)) {
      return const QueryClassification(category: 'creative');
    }
    return const QueryClassification(category: 'reasoning');
  }

  QueryClassification _fullClassify(String lower, String original) {
    // 1. Detect research intent
    final isResearch = _detectResearch(lower);

    // 2. Detect complexity
    final isComplex = _detectComplexity(lower);

    // 3. Detect topics
    final topics = _detectTopics(lower);

    // 4. Score confidence (lower = less certain about classification)
    final confidence = _scoreConfidence(lower, isResearch, topics);

    // 5. Determine base category
    String category;
    if (isResearch) {
      category = 'research';
    } else if (_codingPatterns.hasMatch(lower)) {
      category = 'coding';
    } else if (_quickPatterns.hasMatch(lower)) {
      category = 'quick';
    } else if (_creativePatterns.hasMatch(lower)) {
      category = 'creative';
    } else {
      category = 'reasoning';
    }

    // 6. Determine if confirmation is needed
    final needsConfirmation = _needsConfirmation(
      isResearch: isResearch,
      isComplex: isComplex,
      confidence: confidence,
      category: category,
      queryLength: lower.length,
    );

    // 7. Build summary
    // (caller will use buildSummary)

    return QueryClassification(
      category: category,
      isResearch: isResearch,
      isComplex: isComplex,
      confidence: confidence,
      needsConfirmation: needsConfirmation,
      detectedTopics: topics,
    );
  }

  bool _detectResearch(String lower) {
    if (_researchExactPhrases.hasMatch(lower)) return true;
    for (final pattern in _researchPatterns) {
      if (pattern.hasMatch(lower)) return true;
    }
    return false;
  }

  bool _detectComplexity(String lower) {
    int score = 0;
    for (final pattern in _complexityPatterns) {
      if (pattern.hasMatch(lower)) score++;
    }
    // Also count question marks and conjunctions as mild complexity signals
    final questionMarks = '?'.allMatches(lower).length;
    if (questionMarks > 1) score++;

    final wordCount = lower.split(RegExp(r'\s+')).length;
    if (wordCount > 15) score++;

    return score >= 2;
  }

  List<String> _detectTopics(String lower) {
    final topics = <String>[];
    for (final entry in _topicPatterns.entries) {
      if (entry.value.hasMatch(lower)) {
        topics.add(entry.key);
      }
    }
    return topics;
  }

  double _scoreConfidence(String lower, bool isResearch, List<String> topics) {
    double confidence = 0.8;

    // Boost confidence for clear signals
    if (isResearch) confidence += 0.1;
    if (topics.isNotEmpty) confidence += 0.05;

    // Reduce confidence for very short or very vague queries
    final wordCount = lower.split(RegExp(r'\s+')).length;
    if (wordCount <= 3) confidence -= 0.2;
    if (wordCount <= 5) confidence -= 0.05;

    // Reduce confidence if no clear category signal matched
    final hasCodingSignal = _codingPatterns.hasMatch(lower);
    final hasQuickSignal = _quickPatterns.hasMatch(lower);
    final hasCreativeSignal = _creativePatterns.hasMatch(lower);
    if (!hasCodingSignal && !hasQuickSignal && !hasCreativeSignal && !isResearch) {
      confidence -= 0.15;
    }

    return confidence.clamp(0.0, 1.0);
  }

  bool _needsConfirmation({
    required bool isResearch,
    required bool isComplex,
    required double confidence,
    required String category,
    required int queryLength,
  }) {
    // Always confirm research queries — user wants to ensure we understood
    if (isResearch) return true;

    // Confirm complex multi-part queries
    if (isComplex) return true;

    // Confirm low-confidence classifications (might be going off on wrong path)
    if (confidence < 0.5) return true;

    return false;
  }

  /// Build a plain-language summary of what ARYA understood.
  String buildSummary(QueryClassification classification, String query) {
    final buffer = StringBuffer();

    // Acknowledge what we heard
    if (classification.detectedTopics.isNotEmpty) {
      final topicList = classification.detectedTopics.join(' and ');
      buffer.write('I hear a $topicList question. ');
    }

    // Describe the category
    switch (classification.category) {
      case 'research':
        buffer.write('This looks like a research question. ');
        buffer.write('I will look at both the accepted view and any minority or dissenting perspectives. ');
        break;
      case 'coding':
        buffer.write('This is a coding question. ');
        break;
      case 'quick':
        buffer.write('This is a quick factual question. ');
        break;
      case 'creative':
        buffer.write('This is a creative writing request. ');
        break;
      case 'reasoning':
        buffer.write('This is a reasoning or analysis question. ');
        break;
    }

    // If complex, acknowledge that
    if (classification.isComplex) {
      buffer.write('It looks like a multi-part or detailed question. ');
    }

    // If low confidence, say so honestly
    if (classification.confidence < 0.5) {
      buffer.write('I am not fully sure I understood the intent. ');
    }

    // Offer to proceed
    buffer.write('Should I go ahead?');

    return buffer.toString();
  }
}
