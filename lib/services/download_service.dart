// lib/services/download_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:flutter/foundation.dart';

import '../models/video_item.dart';
import '../models/downloaded_track.dart';
import 'db_service.dart';

class DownloadService {
  static DownloadService? _instance;
  DownloadService._();
  factory DownloadService() => _instance ??= DownloadService._();

  final YoutubeExplode _yt = YoutubeExplode();
  final Map<String, bool> _activeCancelTokens = {};

  void init() {}

  Future<void> cancelActiveDownload(String videoId) async {
    _activeCancelTokens[videoId] = true;
    try {
      final dir = await _getDownloadDir();
      for (final ext in ['m4a', 'mp4', 'webm']) {
        final file = File('${dir.path}/$videoId.$ext');
        if (await file.exists()) await file.delete();
      }
    } catch (_) {}
  }

  /// Mendapatkan direktori download yang tersedia
  Future<Directory> _getDownloadDir() async {
    try {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        final dir = Directory('${extDir.path}/downloads');
        if (!await dir.exists()) await dir.create(recursive: true);
        return dir;
      }
    } catch (_) {}
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/downloads');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Ambil URL audio stream langsung dari Innertube Android API
  Future<(String, int, String)?> _getInnertubeAudioStream(String videoId) async {
    final ua = 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip';
    final httpClient = http.Client();
    try {
      final resp = await httpClient.post(
        Uri.parse('https://www.youtube.com/youtubei/v1/player'),
        headers: {
          'User-Agent': ua,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'context': {
            'client': {
              'clientName': 'ANDROID',
              'clientVersion': '20.10.38',
              'androidSdkVersion': 30,
              'userAgent': ua,
              'hl': 'en',
              'gl': 'US',
            }
          },
          'videoId': videoId,
        }),
      ).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final formats = (data['streamingData']?['adaptiveFormats'] as List?) ?? [];
        final audioStreams = formats.where((f) {
          final mime = f['mimeType'] as String? ?? '';
          return mime.startsWith('audio/') && f['url'] != null;
        }).toList();

        if (audioStreams.isNotEmpty) {
          audioStreams.sort((a, b) {
            final a140 = (a['itag'] == 140) ? 1 : 0;
            final b140 = (b['itag'] == 140) ? 1 : 0;
            if (a140 != b140) return b140.compareTo(a140);
            return ((b['bitrate'] as int?) ?? 0).compareTo((a['bitrate'] as int?) ?? 0);
          });

          final chosen = audioStreams.first;
          final rawUrl = chosen['url'] as String;
          final streamUrl = rawUrl.contains('?')
              ? '$rawUrl&rn=1&rbuf=0&ratebypass=yes'
              : '$rawUrl?rn=1&rbuf=0&ratebypass=yes';
          final clen = int.tryParse(chosen['contentLength']?.toString() ?? '0') ?? 0;
          final mime = chosen['mimeType'] as String? ?? 'audio/mp4';
          final ext = mime.contains('webm') ? 'webm' : 'm4a';
          return (streamUrl, clen, ext);
        }
      }
    } catch (e) {
      debugPrint('[Download] Innertube stream resolution error: $e');
    } finally {
      httpClient.close();
    }
    return null;
  }

  /// Mengunduh audio lagu ke file lokal
  Future<void> downloadVideoNative(
    VideoItem video, {
    required Function(double progress) onProgress,
    required Function(DownloadedTrack track) onComplete,
    required Function(String error) onError,
  }) async {
    _activeCancelTokens[video.videoId] = false;
    IOSink? fileStream;
    try {
      debugPrint('[Download] Mulai unduhan: ${video.title}');

      final downloadDir = await _getDownloadDir();
      final streamInfo = await _getInnertubeAudioStream(video.videoId);

      if (streamInfo != null) {
        final (url, totalBytes, ext) = streamInfo;
        final localPath = '${downloadDir.path}/${video.videoId}.$ext';
        final file = File(localPath);
        fileStream = file.openWrite();

        final request = http.Request('GET', Uri.parse(url));
        request.headers['User-Agent'] =
            'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip';
        
        final client = http.Client();
        final response = await client.send(request);

        int downloadedBytes = 0;
        final length = totalBytes > 0 ? totalBytes : (response.contentLength ?? 0);

        await for (final chunk in response.stream) {
          if (_activeCancelTokens[video.videoId] == true) {
            await fileStream.close();
            if (await file.exists()) await file.delete();
            client.close();
            onError('Unduhan dibatalkan');
            return;
          }
          downloadedBytes += chunk.length;
          fileStream.add(chunk);
          if (length > 0) {
            onProgress((downloadedBytes / length).clamp(0.0, 1.0));
          }
        }

        await fileStream.flush();
        await fileStream.close();
        client.close();

        final track = DownloadedTrack(
          videoId: video.videoId,
          title: video.title,
          channelTitle: video.channelTitle,
          thumbnailUrl: video.thumbnailUrl,
          durationSeconds: video.durationSeconds,
          localPath: localPath,
          downloadedAt: DateTime.now(),
          fileSizeBytes: file.existsSync() ? file.lengthSync() : 0,
        );
        await DbService().insertDownload(track);
        onComplete(track);
        return;
      }

      // Fallback via youtube_explode_dart
      final manifest = await _yt.videos.streamsClient.getManifest(video.videoId);
      if (manifest.audioOnly.isEmpty) {
        throw Exception('Tidak ada stream audio yang tersedia.');
      }

      final ytStreamInfo = manifest.audioOnly.withHighestBitrate();
      final ext = ytStreamInfo.container.name;
      final localPath = '${downloadDir.path}/${video.videoId}.$ext';
      final file = File(localPath);
      fileStream = file.openWrite();

      final stream = _yt.videos.streamsClient.get(ytStreamInfo);
      final totalBytes = ytStreamInfo.size.totalBytes;
      int downloadedBytes = 0;

      await for (final data in stream) {
        if (_activeCancelTokens[video.videoId] == true) {
          await fileStream.close();
          if (await file.exists()) await file.delete();
          onError('Unduhan dibatalkan');
          return;
        }
        downloadedBytes += data.length;
        final progress = totalBytes > 0 ? downloadedBytes / totalBytes : 0.0;
        onProgress(progress.clamp(0.0, 1.0));
        fileStream.add(data);
      }

      await fileStream.flush();
      await fileStream.close();

      final track = DownloadedTrack(
        videoId: video.videoId,
        title: video.title,
        channelTitle: video.channelTitle,
        thumbnailUrl: video.thumbnailUrl,
        durationSeconds: video.durationSeconds,
        localPath: localPath,
        downloadedAt: DateTime.now(),
        fileSizeBytes: file.existsSync() ? file.lengthSync() : 0,
      );
      await DbService().insertDownload(track);
      onComplete(track);
    } catch (e) {
      await fileStream?.close();
      debugPrint('[Download] Gagal: $e');
      onError(e.toString());
    } finally {
      _activeCancelTokens.remove(video.videoId);
    }
  }

  Future<void> deleteDownload(String videoId) async {
    try {
      final track = await DbService().getDownload(videoId);
      if (track != null) {
        final file = File(track.localPath);
        if (await file.exists()) await file.delete();
        await DbService().deleteDownload(videoId);
        debugPrint('[Download] Dihapus: ${track.title}');
      }
    } catch (e) {
      debugPrint('[Download] Gagal hapus: $e');
    }
  }
}
