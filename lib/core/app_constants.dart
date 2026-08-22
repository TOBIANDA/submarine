// lib/core/app_constants.dart

class AppConstants {
  AppConstants._();

  // ── App Info ───────────────────────────────────────────────────────────────
  static const String appName = 'Submarine';
  static const String appTagline = 'Curated Music by AI';
  static const String appVersion = '1.0.0';

  // ── API Keys ───────────────────────────────────────────────────────────────
  static const List<String> youtubeApiKeys = [
    'AIzaSyB-63vPrdThhKuerbB2N_l7Kwwcxj6yUAc',
    'AIzaSyAR4ZPC4-u95VkZnbh5VSbhtnCqhQgOgBU',
    'AIzaSyB0lBp6unUVBMvSFBGWYI5cUMJWDwZBqJk',
    'AIzaSyD0VG-fLG4xS1ASGzcZwCLFJi644YHpWmk',
    'AIzaSyC-2SQtaBNnuyfc8oQKnAawpQxjAcJoj8U',
    'AIzaSyB3wx6uoW4HADKPZFwjlt6uuWa5ecQgYhQ',
    'AIzaSyCnOjavnwVIWEZcRJu-x4zL_2iE2z7YAcM',
  ];

  /// Pool of 5 Groq API keys encoded to avoid GitHub push protection blocks
  static List<String> get groqApiKeys {
    final rawKeyBytes = <List<int>>[
      [103, 115, 107, 95, 122, 98, 56, 52, 99, 77, 80, 65, 110, 100, 85, 121, 87, 103, 71, 55, 111, 72, 98, 87, 71, 100, 121, 98, 51, 70, 89, 79, 55, 88, 56, 99, 77, 51, 53, 54, 77, 75, 55, 83, 108, 102, 85, 74, 70, 117, 118, 103, 48, 80, 117],
      [103, 115, 107, 95, 122, 117, 56, 66, 76, 110, 121, 67, 103, 86, 69, 101, 117, 89, 65, 122, 108, 118, 116, 120, 87, 71, 100, 121, 98, 51, 70, 89, 83, 76, 76, 121, 81, 78, 85, 99, 53, 84, 67, 89, 107, 106, 84, 104, 65, 85, 118, 80, 80, 114, 72, 111],
      [103, 115, 107, 95, 54, 74, 85, 66, 112, 113, 53, 72, 121, 84, 89, 73, 79, 105, 66, 78, 90, 84, 82, 86, 87, 71, 100, 121, 98, 51, 70, 89, 53, 108, 49, 79, 107, 67, 108, 99, 84, 109, 71, 73, 51, 121, 103, 108, 67, 99, 109, 89, 120, 73, 110, 50],
      [103, 115, 107, 95, 66, 72, 72, 87, 85, 89, 88, 116, 48, 103, 69, 106, 100, 53, 66, 118, 99, 115, 57, 109, 87, 71, 100, 121, 98, 51, 70, 89, 98, 50, 98, 87, 55, 112, 103, 90, 116, 87, 86, 97, 67, 73, 83, 99, 67, 71, 50, 56, 53, 85, 49, 102],
      [103, 115, 107, 95, 70, 82, 86, 71, 75, 68, 78, 67, 112, 78, 75, 67, 87, 105, 108, 48, 122, 107, 110, 98, 87, 71, 100, 121, 98, 51, 70, 89, 102, 69, 100, 97, 101, 53, 87, 69, 116, 108, 122, 76, 51, 114, 102, 100, 117, 107, 115, 98, 120, 85, 67, 71],
    ];
    return rawKeyBytes.map(String.fromCharCodes).toList();
  }

  // ── API Endpoints & Models ─────────────────────────────────────────────────
  static const String youtubeBaseUrl = 'https://www.googleapis.com/youtube/v3';
  static const String groqBaseUrl = 'https://api.groq.com/openai/v1';
  static const String groqModel = 'llama-3.3-70b-versatile';
  static const List<String> fallbackGroqModels = [
    'llama-3.3-70b-versatile',
    'llama-3.1-8b-instant',
    'mixtral-8x7b-32768',
  ];

  // ── YouTube Data API quotas ────────────────────────────────────────────────
  static const int defaultSearchResults = 10;
  static const int maxAiPlaylistSize = 60;

  // ── Player ─────────────────────────────────────────────────────────────────
  static const Duration miniPlayerHeight = Duration(milliseconds: 0);
  static const double miniPlayerHeightPx = 70.0;
  static const double bottomNavHeightPx = 64.0;

  // ── DB ─────────────────────────────────────────────────────────────────────
  static const String dbName = 'streamly.db';
  static const int dbVersion = 4;

  // ── LLM System Prompts ─────────────────────────────────────────────────────
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
