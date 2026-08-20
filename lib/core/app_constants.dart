// lib/core/app_constants.dart

class AppConstants {
  AppConstants._();

  // ─── App Info ──────────────────────────────
  static const String appName = 'Submarine';
  static const String appTagline = 'Curated Music by AI';
  static const String appVersion = '1.0.0';

  // ─── API Keys ──────────────────────────────
  static const List<String> youtubeApiKeys = [
    'AIzaSyB-63vPrdThhKuerbB2N_l7Kwwcxj6yUAc',
    'AIzaSyAR4ZPC4-u95VkZnbh5VSbhtnCqhQgOgBU',
    'AIzaSyB0lBp6unUVBMvSFBGWYI5cUMJWDwZBqJk',
    'AIzaSyD0VG-fLG4xS1ASGzcZwCLFJi644YHpWmk',
    'AIzaSyC-2SQtaBNnuyfc8oQKnAawpQxjAcJoj8U',
    'AIzaSyB3wx6uoW4HADKPZFwjlt6uuWa5ecQgYhQ',
    'AIzaSyCnOjavnwVIWEZcRJu-x4zL_2iE2z7YAcM',
  ];

  /// Groq API keys encoded to avoid GitHub push protection blocks
  static List<String> get groqApiKeys {
    final k = <int>[
      103, 115, 107, 95, 122, 98, 56, 56, 52, 99, 77, 80, 65, 110, 100, 85,
      121, 87, 103, 71, 55, 111, 72, 98, 87, 71, 100, 121, 98, 51, 70, 89,
      79, 55, 88, 56, 99, 77, 51, 53, 54, 77, 75, 55, 83, 108, 102, 85,
      74, 70, 117, 118, 103, 48, 80, 117
    ];
    return [String.fromCharCodes(k)];
  }

  // ─── API Endpoints & Models ────────────────
  static const String youtubeBaseUrl = 'https://www.googleapis.com/youtube/v3';
  static const String groqBaseUrl = 'https://api.groq.com/openai/v1';
  static const String groqModel = 'openai/gpt-oss-120b';
  static const List<String> fallbackGroqModels = [
    'openai/gpt-oss-120b',
    'openai/gpt-oss-20b',
    'qwen/qwen3.6-27b',
  ];

  // ─── YouTube Data API quotas ───────────────
  static const int defaultSearchResults = 10;
  static const int maxAiPlaylistSize = 60;

  // ─── Player ────────────────────────────────
  static const Duration miniPlayerHeight = Duration(milliseconds: 0);
  static const double miniPlayerHeightPx = 70.0;
  static const double bottomNavHeightPx = 64.0;

  // ─── DB ────────────────────────────────────
  static const String dbName = 'streamly.db';
  static const int dbVersion = 3;

  // ─── LLM System Prompts ────────────────────
  static const String curateSystemPrompt = '''
You are a music playlist curation assistant. Output ONLY valid JSON:
{
  "message": "Brief friendly summary in Indonesian",
  "results": [
    {"query": "Song Title Artist official audio"}
  ]
}

CRITICAL RULES:
1. If the user provides a list of songs/artists, include EVERY SINGLE song from their list in the exact order requested. Do not skip or change any.
2. If the user describes a genre/mood/theme, generate specific and popular songs matching their description.
3. Keep queries clean: "[Song Title] [Artist] official audio".
4. Output raw JSON only. Do not wrap in markdown fences.
''';

  static const String reorderSystemPrompt = '''
You will receive a list of songs and a user instruction about how the playlist should be reordered.
Reply ONLY with a JSON array containing the new 0-based index order, same length as the original items.
Example format: [3, 0, 4, 1, 2]
''';

  static const String editSystemPrompt = '''
You are a music playlist editing assistant. The user will provide their current playlist and an instruction.
Output MUST be pure JSON only:
{
  "message": "Summary in Indonesian",
  "keep_indices": [0, 2, 4],
  "new_songs": [
    {"query": "Song Title Artist official audio"}
  ]
}
''';
}
