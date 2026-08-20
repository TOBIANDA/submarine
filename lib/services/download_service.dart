// lib/services/download_service.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/downloaded_track.dart';
import '../models/video_item.dart';
import 'db_service.dart';

class DownloadService {
  static DownloadService? _instance;
  DownloadService._();
  factory DownloadService() => _instance ??= DownloadService._();

  static const _extractorChannel = MethodChannel('com.submarine/extractor');
  final Map<String, bool> _activeCancelTokens = {};

  void init() {
    _cleanCorruptedDownloads();
  }

  /// Bersihkan file 0-byte atau rusak dari storage dan database
  Future<void> _cleanCorruptedDownloads() async {
    try {
      final downloads = await DbService().getAllDownloads();
      for (final track in downloads) {
        final file = File(track.localPath);
        if (!file.existsSync() || file.lengthSync() < 50000) {
          debugPrint('[Download] Menghapus track korup (0-byte): ${track.title}');
          if (file.existsSync()) await file.delete();
          await DbService().deleteDownload(track.videoId);
        }
      }
    } catch (e) {
      debugPrint('[Download] Error cleaning corrupted downloads: $e');
    }
  }

  Future<void> cancelActiveDownload(String videoId) async {
    _activeCancelTokens[videoId] = true;
    try {
      final dir = await _getDownloadDir();
      for (final ext in ['m4a', 'mp4', 'webm', 'opus']) {
        final file = File('${dir.path}/$videoId.$ext');
        if (await file.exists()) await file.delete();
      }
    } catch (_) {}
  }

  /// Mendapatkan direktori download yang konsisten untuk offline playback
  Future<Directory> _getDownloadDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/downloads');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Mengunduh audio lagu ke file lokal menggunakan NewPipeExtractor
  Future<void> downloadVideoNative(
    VideoItem video, {
    required Function(double progress) onProgress,
    required Function(DownloadedTrack track) onComplete,
    required Function(String error) onError,
  }) async {
    _activeCancelTokens[video.videoId] = false;
    IOSink? fileStream;
    http.Client? client;
    try {
      debugPrint('[Download] Meminta URL stream via NewPipeExtractor: ${video.title}');

      final result = await _extractorChannel.invokeMethod<Map>('getAudioStreamUrl', {
        'videoId': video.videoId,
      });

      if (result == null || result['url'] == null) {
        throw Exception('Gagal mendapatkan link download dari NewPipeExtractor');
      }

      final streamUrl = result['url'] as String;
      final formatName = (result['format'] as String? ?? 'm4a').toLowerCase();
      final ext = formatName.contains('webm') || formatName.contains('opus') ? 'webm' : 'm4a';

      final downloadDir = await _getDownloadDir();
      final localPath = '${downloadDir.path}/${video.videoId}.$ext';
      final file = File(localPath);
      if (file.existsSync()) file.deleteSync();

      client = http.Client();
      final request = http.Request('GET', Uri.parse(streamUrl));
      request.headers['User-Agent'] =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

      final response = await client.send(request);

      if (response.statusCode != 200 && response.statusCode != 206) {
        throw Exception('Download stream gagal dengan kode HTTP ${response.statusCode}');
      }

      fileStream = file.openWrite();
      int downloadedBytes = 0;
      final length = response.contentLength ?? 0;

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

      final finalSize = file.existsSync() ? file.lengthSync() : 0;
      if (finalSize < 50000) {
        if (file.existsSync()) await file.delete();
        throw Exception('File unduhan tidak lengkap ($finalSize bytes)');
      }

      final track = DownloadedTrack(
        videoId: video.videoId,
        title: video.title,
        channelTitle: video.channelTitle,
        thumbnailUrl: video.thumbnailUrl,
        durationSeconds: video.durationSeconds,
        localPath: localPath,
        downloadedAt: DateTime.now(),
        fileSizeBytes: finalSize,
      );
      await DbService().insertDownload(track);
      debugPrint('[Download] Sukses tersimpan: $localPath ($finalSize bytes)');
      onComplete(track);
    } catch (e) {
      await fileStream?.close();
      client?.close();
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
