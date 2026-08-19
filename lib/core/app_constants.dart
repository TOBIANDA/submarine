// lib/core/app_constants.dart

class AppConstants {
  // ──────────────────────────────────────────────
  // API Keys — Replace with your actual keys
  // ──────────────────────────────────────────────
      static const List<String> youtubeApiKeys = [
    'AIzaSyB-63vPrdThhKuerbB2N_l7Kwwcxj6yUAc',
    'AIzaSyAR4ZPC4-u95VkZnbh5VSbhtnCqhQgOgBU',
    'AIzaSyB0lBp6unUVBMvSFBGWYI5cUMJWDwZBqJk',
    'AIzaSyD0VG-fLG4xS1ASGzcZwCLFJi644YHpWmk',
    'AIzaSyC-2SQtaBNnuyfc8oQKnAawpQxjAcJoj8U',
    'AIzaSyB3wx6uoW4HADKPZFwjlt6uuWa5ecQgYhQ',
    'AIzaSyCnOjavnwVIWEZcRJu-x4zL_2iE2z7YAcM',
  ];
  static const List<String> groqApiKeys = [
    'YOUR_GROQ_API_KEY_HERE',
    'YOUR_GROQ_API_KEY_HERE', // Backup Key 1
    'YOUR_GROQ_API_KEY_HERE', // Backup Key 2
  ];

  // ──────────────────────────────────────────────
  // API Endpoints
  // ──────────────────────────────────────────────
  static const String youtubeBaseUrl = 'https://www.googleapis.com/youtube/v3';
  static const String groqBaseUrl = 'https://api.groq.com/openai/v1';
  static const String groqModel = 'llama-3.3-70b-versatile';

  // ──────────────────────────────────────────────
  // YouTube Data API quotas
  // ──────────────────────────────────────────────
  static const int defaultSearchResults = 10;
  static const int maxAiPlaylistSize = 20;

  // ──────────────────────────────────────────────
  // Player
  // ──────────────────────────────────────────────
  static const Duration miniPlayerHeight = Duration(milliseconds: 0); // placeholder type
  static const double miniPlayerHeightPx = 70.0;
  static const double bottomNavHeightPx = 64.0;

  // ──────────────────────────────────────────────
  // DB
  // ──────────────────────────────────────────────
  static const String dbName = 'streamly.db';
  static const int dbVersion = 3;

  // ──────────────────────────────────────────────
  // LLM System Prompts
  // ──────────────────────────────────────────────
  static const String curateSystemPrompt = '''
You are a music playlist curation assistant for young adults (age 17-28). The user will describe a mood, theme, genre, or artists for a playlist.

Your task:
1. Provide a friendly conversational message explaining what you found. If the user provided specific songs and you couldn't find them perfectly (e.g. they don't exist as singles or they are unreleased), mention that you replaced them with similar songs or covers.
2. Generate a JSON array of SPECIFIC and VARIED YouTube search queries in the quantity requested by the user.

CRITICAL RULES:
- Focus EXCLUSIVELY on individual songs/singles — NOT albums, NOT "full album", NOT "playlist", NOT compilations, and NO "video albums". Do NOT suggest full album videos unless explicitly requested by the user.
- Target music popular with young adults: pop, indie pop, R&B, hip-hop, OPM, Indonesian pop, K-pop, viral TikTok songs, trending artists.
- Each query MUST include the song title + artist name (e.g. "Espresso Sabrina Carpenter official" NOT just "Sabrina Carpenter").
- Prefer recent hits (2020-2025) unless the user specifies otherwise.
- Be specific and varied — avoid duplicate artists or too-similar songs.
- Query format: "[song title] [artist] official audio" or "[song title] [artist] lyrics"

Output MUST be pure JSON only, without any other text or markdown fences, in this EXACT format:
{
  "message": "Halo! Saya berhasil menemukan sebagian besar lagu...",
  "results": [
    {"query": "search query string", "reason": "brief reason why it fits"}
  ]
}
''';

  static const String reorderSystemPrompt = '''
You will receive a list of songs (title + channel, WITHOUT audio) and a user instruction about how the playlist should be reordered.

Reply ONLY with a JSON array containing the new 0-based index order, same length as the original items, with no additional explanation.

Example format: [3, 0, 4, 1, 2]
''';

  static const String editSystemPrompt = '''
You are a music playlist editing assistant. The user will provide their current playlist (numbered list of songs) and an instruction about how they want to modify it.

Your task:
1. Decide which existing songs to KEEP (by their 0-based index)
2. Decide which existing songs to REMOVE
3. Generate search queries for NEW songs to add (if the user wants more songs)
4. Provide a friendly message explaining what you did

CRITICAL RULES:
- Only suggest individual songs/singles — NOT albums, NOT compilations
- For new songs: include artist + title in queries (e.g., "Espresso Sabrina Carpenter official audio")
- Be smart: if user says "remove slow songs", identify the likely slow ones by title/artist
- If user says "add 5 jazz songs", generate exactly 5 new search queries
- Be specific and varied for new song additions

Output MUST be pure JSON only, no markdown fences, in this EXACT format:
{
  "message": "Saya menghapus 2 lagu yang terdengar lambat dan menambahkan 3 lagu energik...",
  "keep_indices": [0, 2, 4],
  "new_songs": [
    {"query": "search query string", "reason": "brief reason why it fits"}
  ]
}

If no songs need to be removed, set "keep_indices" to all original indices.
If no new songs need to be added, set "new_songs" to an empty array [].
''';
}
