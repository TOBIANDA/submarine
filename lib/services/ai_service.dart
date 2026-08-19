// lib/services/ai_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import '../models/video_item.dart';
import '../core/app_constants.dart';

class AiCurationResult {
  final String message;
  final List<String> queries;
  final List<String> reasons;

  AiCurationResult({required this.message, required this.queries, required this.reasons});
}

class AiEditResult {
  final String message;
  /// Indeks dari playlist asli yang harus DIPERTAHANKAN
  final List<int> keepIndices;
  /// Query pencarian untuk lagu-lagu BARU yang akan ditambahkan
  final List<String> newSongQueries;
  final List<String> newSongReasons;

  AiEditResult({
    required this.message,
    required this.keepIndices,
    required this.newSongQueries,
    required this.newSongReasons,
  });
}

class AiService {
  static AiService? _instance;
  AiService._();
  factory AiService() => _instance ??= AiService._();

  /// Ask Groq to generate search queries for a playlist description
  Future<AiCurationResult> curatePlaylist(
      String description, {int count = 10}) async {
    final userMessage =
        '$description\n\nGenerate exactly $count search queries.';

    final response = await _callGroq(
      system: AppConstants.curateSystemPrompt,
      userMessage: userMessage,
    );

    // Strip markdown fences if the model wrapped the JSON
    final cleaned = _stripMarkdown(response);

    try {
      final jsonMap = jsonDecode(cleaned) as Map<String, dynamic>;
      final message = jsonMap['message'] as String? ?? 'Berikut playlist pilihan saya:';
      final jsonList = jsonMap['results'] as List<dynamic>;
      
      final queries = <String>[];
      final reasons = <String>[];
      for (final item in jsonList) {
        final map = item as Map<String, dynamic>;
        queries.add(map['query'] as String);
        reasons.add(map['reason'] as String? ?? '');
      }
      return AiCurationResult(message: message, queries: queries, reasons: reasons);
    } catch (e) {
      throw Exception(
          'Failed to parse AI curation response: $e\n\nRaw: $response');
    }
  }

  /// Ask Groq to reorder a playlist based on user instruction
  /// Returns new ordering as list of original indices
  Future<List<int>> reorderPlaylist(
      List<VideoItem> items, String instruction) async {
    final itemList = items
        .asMap()
        .entries
        .map((e) => '${e.key}: ${e.value.title} — ${e.value.channelTitle}')
        .join('\n');

    final userMessage = '''
Playlist items:
$itemList

Instruction: $instruction
''';

    final response = await _callGroq(
      system: AppConstants.reorderSystemPrompt,
      userMessage: userMessage,
    );

    final cleaned = _stripMarkdown(response);

    try {
      final jsonList = jsonDecode(cleaned) as List<dynamic>;
      return jsonList.map((e) => e as int).toList();
    } catch (e) {
      throw Exception(
          'Failed to parse AI reorder response: $e\n\nRaw: $response');
    }
  }

  /// Meminta AI untuk mengedit playlist berdasarkan instruksi user.
  /// AI akan memutuskan lagu mana yang dihapus dan lagu baru apa yang ditambahkan.
  Future<AiEditResult> editPlaylist(
      List<VideoItem> items, String instruction) async {
    final itemList = items
        .asMap()
        .entries
        .map((e) => '${e.key}: ${e.value.title} — ${e.value.channelTitle}')
        .join('\n');

    final userMessage = '''
Current playlist (${items.length} songs):
$itemList

Instruction: $instruction
''';

    final response = await _callGroq(
      system: AppConstants.editSystemPrompt,
      userMessage: userMessage,
    );

    final cleaned = _stripMarkdown(response);

    try {
      final jsonMap = jsonDecode(cleaned) as Map<String, dynamic>;
      final message = jsonMap['message'] as String? ?? 'Playlist telah diperbarui!';
      
      final keepIndices = (jsonMap['keep_indices'] as List<dynamic>)
          .map((e) => e as int)
          .toList();
      
      final newSongsRaw = jsonMap['new_songs'] as List<dynamic>? ?? [];
      final newSongQueries = <String>[];
      final newSongReasons = <String>[];
      for (final item in newSongsRaw) {
        final map = item as Map<String, dynamic>;
        newSongQueries.add(map['query'] as String);
        newSongReasons.add(map['reason'] as String? ?? '');
      }

      return AiEditResult(
        message: message,
        keepIndices: keepIndices,
        newSongQueries: newSongQueries,
        newSongReasons: newSongReasons,
      );
    } catch (e) {
      throw Exception(
          'Failed to parse AI edit response: $e\n\nRaw: $response');
    }
  }

  /// Meminta Groq untuk menyarankan satu lagu berikutnya (Fallback jika YouTube gagal)
    /// Meminta Groq untuk menyarankan satu lagu berikutnya yang BERBEDA (Anti-Duplikat)
  Future<String?> recommendNextSong(String currentTitle, String currentArtist) async {
    final cleanTitle = currentTitle
        .replaceAll(RegExp(r'\(.*?\)|\[.*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'official\s*(video|audio|lyrics|music video)?', caseSensitive: false), '')
        .trim();

    final system = '''You are an expert music curator and recommendation engine for a high-end music app. 
The user just finished listening to "$cleanTitle" by "$currentArtist". 

YOUR TASK:
Recommend EXACTLY ONE SIMILAR song (by the same artist or by a closely related artist/genre) that provides a great continuous listening experience.

CRITICAL DEDUPLICATION RULES:
1. STRICTLY FORBIDDEN to recommend "$cleanTitle" or any remix, cover, acoustic, or re-upload of "$cleanTitle".
2. It MUST be a COMPLETELY DIFFERENT song (e.g. if the user played "18" by One Direction, recommend "Night Changes" by One Direction, or "Sign of the Times" by Harry Styles, or "Lie to Me" by 5 Seconds of Summer).
3. Do NOT recommend albums, compilations, mixes, or podcasts.
4. Output ONLY the search query for the song, e.g. "Artist - Song Title official audio". Do not include any other text, quotes, or markdown.''';

    try {
      final response = await _callGroq(system: system, userMessage: 'Recommend next distinct song');
      final result = response.trim().replaceAll('"', '').replaceAll("'", "");
      
      // Safety check: if model repeated the same title, ignore
      if (result.toLowerCase().contains(cleanTitle.toLowerCase()) && cleanTitle.length > 3) {
        debugPrint('[AI] Model menyarankan lagu yang sama ($result), abaikan untuk cegah duplikat.');
        return null;
      }
      return result;
    } catch (e) {
      debugPrint('[AI] Failed to recommend next song: $e');
      return null;
    }
  }

  /// Call Groq using OpenAI-compatible Chat Completions API
  Future<String> _callGroq({
    required String system,
    required String userMessage,
  }) async {
    final uri = Uri.parse('${AppConstants.groqBaseUrl}/chat/completions');

    // Gunakan salah satu API key secara acak untuk mencegah rate limit,
    // atau gunakan key pertama jika hanya ada 1.
    final keys = AppConstants.groqApiKeys.where((k) => !k.contains('ISI_API_CADANGAN')).toList();
    final apiKey = keys.isNotEmpty ? (keys.toList()..shuffle()).first : AppConstants.groqApiKeys.first;

    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': AppConstants.groqModel,
        'temperature': 0.7,
        'max_tokens': 8000,
        'messages': [
          {'role': 'system', 'content': system},
          {'role': 'user', 'content': userMessage},
        ],
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
          'Groq API error ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = data['choices'] as List<dynamic>;
    final message = choices.first as Map<String, dynamic>;
    return (message['message'] as Map<String, dynamic>)['content'] as String;
  }

  /// Strip ```json ... ``` markdown fences that LLMs sometimes add
  String _stripMarkdown(String raw) {
    final trimmed = raw.trim();
    // Remove ```json or ``` at start and ``` at end
    final stripped = trimmed
        .replaceFirst(RegExp(r'^```(?:json)?\s*', multiLine: false), '')
        .replaceFirst(RegExp(r'\s*```$', multiLine: false), '');
    return stripped.trim();
  }
}
