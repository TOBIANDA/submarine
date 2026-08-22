// lib/services/ai_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/app_constants.dart';

class AiCurationResult {
  final String message;
  final List<String> queries;

  AiCurationResult({required this.message, required this.queries});
}

class AiEditResult {
  final String message;
  final List<int> keepIndices;
  final List<String> newQueries;

  AiEditResult({
    required this.message,
    required this.keepIndices,
    required this.newQueries,
  });
}

class AiService {
  static AiService? _instance;
  AiService._();
  factory AiService() => _instance ??= AiService._();

  /// Curate a new playlist from user prompt
  Future<AiCurationResult> curatePlaylist(String prompt, {int songCount = 15}) async {
    final userMsg = 'Buatkan playlist dengan tema/deskripsi berikut: "$prompt"\nJumlah lagu: $songCount';

    final rawJson = await _callGroq(
      system: AppConstants.curateSystemPrompt,
      userMessage: userMsg,
      maxTokens: 2000,
    );

    return _parseCurationResponse(rawJson);
  }

  /// Reorder an existing playlist
  Future<List<int>> reorderPlaylist({
    required List<String> songTitles,
    required String instruction,
  }) async {
    final titlesList = songTitles.asMap().entries.map((e) => '${e.key}: ${e.value}').join('\n');
    final userMsg = 'Daftar lagu saat ini:\n$titlesList\n\nInstruksi pengurutan: "$instruction"';

    final rawJson = await _callGroq(
      system: AppConstants.reorderSystemPrompt,
      userMessage: userMsg,
      maxTokens: 500,
    );

    return _parseReorderResponse(rawJson, songTitles.length);
  }

  /// Edit/modify an existing playlist
  Future<AiEditResult> editPlaylist({
    required List<String> currentSongs,
    required String instruction,
  }) async {
    final songList = currentSongs.asMap().entries.map((e) => '[Index ${e.key}] ${e.value}').join('\n');
    final userMsg = 'Playlist saat ini:\n$songList\n\nInstruksi edit: "$instruction"';

    final rawJson = await _callGroq(
      system: AppConstants.editSystemPrompt,
      userMessage: userMsg,
      maxTokens: 1500,
    );

    return _parseEditResponse(rawJson, currentSongs.length);
  }

  /// Multi-Key Round-Robin & Multi-Model resilient Groq API Caller
  Future<String> _callGroq({
    required String system,
    required String userMessage,
    int maxTokens = 1500,
  }) async {
    final uri = Uri.parse('${AppConstants.groqBaseUrl}/chat/completions');
    final keys = (AppConstants.groqApiKeys.toList()..shuffle());
    final modelsToTry = [AppConstants.groqModel, ...AppConstants.fallbackGroqModels].toSet().toList();
    Object? lastError;

    for (final apiKey in keys) {
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
              'temperature': 0.3,
              'max_tokens': maxTokens,
              'messages': [
                {'role': 'system', 'content': system},
                {'role': 'user', 'content': userMessage},
              ],
            }),
          ).timeout(const Duration(seconds: 15));

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final content = data['choices']?[0]?['message']?['content'] as String?;
            if (content != null && content.isNotEmpty) {
              return content;
            }
          } else if (response.statusCode == 429) {
            debugPrint('[AI] Key rate limited (429), trying next key in pool...');
            break; // Break model loop to switch to next API key immediately
          } else {
            debugPrint('[AI] Groq $model error: ${response.statusCode} - ${response.body}');
            lastError = Exception('Groq status: ${response.statusCode}');
          }
        } catch (e) {
          debugPrint('[AI] Attempt error: $e');
          lastError = e;
        }
      }
    }

    throw Exception('Semua kunci AI dan model cadangan sedang sibuk. Silakan coba lagi sebentar lagi: $lastError');
  }

  AiCurationResult _parseCurationResponse(String raw) {
    try {
      final jsonStr = _extractJson(raw);
      final data = jsonDecode(jsonStr);

      final message = data['message'] as String? ?? 'Playlist berhasil dibuat';
      final resultsList = data['results'] as List<dynamic>? ?? [];

      final queries = resultsList
          .map((item) {
            if (item is Map) return item['query']?.toString() ?? '';
            return item.toString();
          })
          .where((q) => q.isNotEmpty)
          .toList();

      return AiCurationResult(message: message, queries: queries);
    } catch (e) {
      debugPrint('[AI] Parse curation error: $e, raw: $raw');
      final lines = raw
          .split('\n')
          .map((l) => l.replaceAll(RegExp(r'^\d+[\.\)]\s*'), '').trim())
          .where((l) => l.isNotEmpty && !l.startsWith('{') && !l.startsWith('}') && !l.startsWith('`'))
          .map((l) => '$l official audio')
          .toList();

      return AiCurationResult(
        message: 'Playlist berhasil dikurasi oleh AI',
        queries: lines.isNotEmpty ? lines : ['top pop hits official audio'],
      );
    }
  }

  List<int> _parseReorderResponse(String raw, int expectedLength) {
    try {
      final jsonStr = _extractJson(raw);
      final decoded = jsonDecode(jsonStr);
      if (decoded is List) {
        final indices = decoded.map((e) => (e as num).toInt()).toList();
        if (indices.length == expectedLength) return indices;
      }
    } catch (_) {}
    return List.generate(expectedLength, (i) => i);
  }

  AiEditResult _parseEditResponse(String raw, int currentCount) {
    try {
      final jsonStr = _extractJson(raw);
      final data = jsonDecode(jsonStr);

      final message = data['message'] as String? ?? 'Playlist berhasil diubah';
      final keepList = (data['keep_indices'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .where((i) => i >= 0 && i < currentCount)
              .toList() ??
          List.generate(currentCount, (i) => i);

      final newSongsList = data['new_songs'] as List<dynamic>? ?? [];
      final newQueries = newSongsList
          .map((item) {
            if (item is Map) return item['query']?.toString() ?? '';
            return item.toString();
          })
          .where((q) => q.isNotEmpty)
          .toList();

      return AiEditResult(
        message: message,
        keepIndices: keepList,
        newQueries: newQueries,
      );
    } catch (e) {
      return AiEditResult(
        message: 'Playlist diperbarui',
        keepIndices: List.generate(currentCount, (i) => i),
        newQueries: [],
      );
    }
  }

  String _extractJson(String text) {
    final cleaned = text.trim();
    if (cleaned.startsWith('```')) {
      final lines = cleaned.split('\n');
      final firstBrace = lines.indexWhere((l) => l.contains('{') || l.contains('['));
      final lastBrace = lines.lastIndexWhere((l) => l.contains('}') || l.contains(']'));
      if (firstBrace != -1 && lastBrace != -1 && lastBrace >= firstBrace) {
        return lines.sublist(firstBrace, lastBrace + 1).join('\n');
      }
    }
    final startObj = cleaned.indexOf('{');
    final startArr = cleaned.indexOf('[');
    final endObj = cleaned.lastIndexOf('}');
    final endArr = cleaned.lastIndexOf(']');

    int start = -1;
    int end = -1;

    if (startObj != -1 && (startArr == -1 || startObj < startArr)) {
      start = startObj;
      end = endObj;
    } else if (startArr != -1) {
      start = startArr;
      end = endArr;
    }

    if (start != -1 && end != -1 && end > start) {
      return cleaned.substring(start, end + 1);
    }

    return cleaned;
  }
}
