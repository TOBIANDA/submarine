// lib/services/youtube_stream_source.dart
import 'dart:io';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/foundation.dart';

/// Custom StreamAudioSource that fetches YouTube audio with proper HTTP headers.
/// This bypasses the 403 error that occurs when ExoPlayer tries to fetch
/// YouTube URLs with its default User-Agent.
class YoutubeStreamAudioSource extends StreamAudioSource {
  final String url;
  final int totalBytes;
  final String mimeType;

  YoutubeStreamAudioSource({
    required this.url,
    required this.totalBytes,
    required this.mimeType,
  });

  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final s = start ?? 0;

    final client = HttpClient();
    client.userAgent = _userAgent;
    
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('Referer', 'https://www.youtube.com/');
      request.headers.set('Origin', 'https://www.youtube.com');

      // Range request for seeking support
      if (end != null) {
        request.headers.set('Range', 'bytes=$s-${end - 1}');
      } else {
        request.headers.set('Range', 'bytes=$s-');
      }

      final response = await request.close();
      final responseLength = end != null ? (end - s) : (totalBytes - s);

      debugPrint('[YTStream] Range $s-${end ?? "end"} -> status ${response.statusCode}, len=$responseLength');

      return StreamAudioResponse(
        sourceLength: totalBytes,
        contentLength: responseLength,
        offset: s,
        stream: response.cast<List<int>>(),
        contentType: mimeType,
      );
    } catch (e) {
      debugPrint('[YTStream] HTTP request failed: $e');
      rethrow;
    }
  }
}
