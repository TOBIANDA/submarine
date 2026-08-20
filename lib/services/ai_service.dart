// lib/services/ai_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/app_constants.dart';
import '../models/video_item.dart';

class AiCurationResult {
  final String message;
  final List<String> queries;
  final List<String> reasons;

  AiCurationResult({required this.message, required this.queries, required this.reasons});
}

class AiEditResult {
  final String message;
  final List<int> keepIndices;
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
      maxTokens: (count * 35 + 400).clamp(600, 2200),
    );

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
  Future<List<int>> reorderPlaylist(
      List<VideoItem> items, String instruction) async {
    final itemList = items
        .asMap()
        .entries
        .map((e) => '${e.key}: ${e.value.title} - ${e.value.channelTitle}')
        .join('\n');

    final userMessage = '''
Playlist items:
$itemList

Instruction: $instruction
''';

    final response = await _callGroq(
      system: AppConstants.reorderSystemPrompt,
      userMessage: userMessage,
      maxTokens: 1000,
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
  Future<AiEditResult> editPlaylist(
      List<VideoItem> items, String instruction) async {
    final itemList = items
        .asMap()
        .entries
        .map((e) => '${e.key}: ${e.value.title} - ${e.value.channelTitle}')
        .join('\n');

    final userMessage = '''
Current playlist (${items.length} songs):
$itemList

Instruction: $instruction
''';

    final response = await _callGroq(
      system: AppConstants.editSystemPrompt,
      userMessage: userMessage,
      maxTokens: 1500,
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

  /// Meminta Groq untuk menyarankan satu lagu berikutnya yang BERBEDA (Anti-Duplikat)
  Future<String?> recommendNextSong(String currentTitle, String currentArtist) async {
    final cleanTitle = currentTitle
        .replaceAll(RegExp(r'\(.*?\)|\[.*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'official\s*(video|audio|lyrics|music video)?', caseSensitive: false), '')
        .trim();

    final system = '''You are an expert music curator. 
The user just finished listening to "$cleanTitle" by "$currentArtist". 

YOUR TASK:
Recommend EXACTLY ONE SIMILAR song (by the same artist or by a related artist) that provides a great continuous listening experience.

CRITICAL RULES:
1. STRICTLY FORBIDDEN to recommend "$cleanTitle" or any remix of it.
2. It MUST be a COMPLETELY DIFFERENT song.
3. Output ONLY the search query, e.g. "Artist - Song Title official audio". Do not include quotes or markdown.''';

    try {
      final response = await _callGroq(
        system: system,
        userMessage: 'Recommend next distinct song',
        maxTokens: 300,
      );
      final result = response.trim().replaceAll('"', '').replaceAll("'", "");
      
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

  /// Call Groq using OpenAI-compatible Chat Completions API with fallback models
  Future<String> _callGroq({
    required String system,
    required String userMessage,
    int maxTokens = 1500,
  }) async {
    final uri = Uri.parse('${AppConstants.groqBaseUrl}/chat/completions');
    final keys = AppConstants.groqApiKeys.where((k) => !k.contains('ISI_API_CADANGAN')).toList();
    final apiKey = keys.isNotEmpty ? (keys.toList()..shuffle()).first : AppConstants.groqApiKeys.first;

    final modelsToTry = [AppConstants.groqModel, ...AppConstants.fallbackGroqModels].toSet().toList();
    Object? lastError;

    for (final model in modelsToTry) {
      try {
        final response = await http.post(
          uri,
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'temperature': 0.6,
            'max_tokens': maxTokens,
            'messages': [
              {'role': 'system', 'content': system},
              {'role': 'user', 'content': userMessage},
            ],
          }),
        ).timeout(const Duration(seconds: 25));

        if (response.statusCode == 200) {
          final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
          final content = jsonBody['choices'][0]['message']['content'] as String;
          return content;
        } else {
          lastError = 'Groq API error ${response.statusCode}: ${response.body}';
          debugPrint('[AI] Model $model returned ${response.statusCode}, trying next model...');
        }
      } catch (e) {
        lastError = e;
        debugPrint('[AI] Model $model exception: $e, trying next model...');
      }
    }

    throw Exception(lastError ?? 'All Groq models failed');
  }

  String _stripMarkdown(String raw) {
    var text = raw.trim();
    if (text.startsWith('```json')) {
      text = text.substring(7);
    } else if (text.startsWith('```')) {
      text = text.substring(3);
    }
    if (text.endsWith('```')) {
      text = text.substring(0, text.length - 3);
    }
    return text.trim();
  }
}
