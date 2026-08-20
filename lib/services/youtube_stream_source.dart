// lib/services/youtube_stream_source.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Downloads YouTube audio stream to a temporary file using
/// youtube_explode_dart's StreamsClient (which handles all HTTP auth/throttling).
/// Returns the file path once enough data is available for playback.
class YoutubeStreamDownloader {
  static Future<String> downloadToTempFile({
    required YoutubeExplode yt,
    required StreamInfo streamInfo,
    required String videoId,
  }) async {
    final dir = await getTemporaryDirectory();
    final ext = streamInfo.container.name == 'webm' ? 'webm' : 'm4a';
    final filePath = '${dir.path}/yt_audio_$videoId.$ext';
    final file = File(filePath);

    // If file already exists and is large enough, reuse it
    if (await file.exists() && await file.length() > 100000) {
      debugPrint('[YTDownloader] Reusing cached file: $filePath');
      return filePath;
    }

    debugPrint('[YTDownloader] Downloading stream to: $filePath');
    final stream = yt.videos.streamsClient.get(streamInfo);
    final sink = file.openWrite();
    int totalBytes = 0;

    await for (final chunk in stream) {
      sink.add(chunk);
      totalBytes += chunk.length;
    }

    await sink.flush();
    await sink.close();
    debugPrint('[YTDownloader] Download complete: ${totalBytes} bytes');
    return filePath;
  }
}
