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

  /// Bersihkan file yang tidak lengkap (< 800KB) dari storage dan database
  Future<void> _cleanCorruptedDownloads() async {
    try {
      final downloads = await DbService().getAllDownloads();
      for (final track in downloads) {
        final file = File(track.localPath);
        if (!file.existsSync() || file.lengthSync() < 800000) {
          debugPrint('[Download] Membersihkan file download tidak lengkap: ${track.title}');
          if (file.existsSync()) await file.delete();
          await DbService().deleteDownload(track.videoId);
        }
      }
      
      // Bersihkan juga file yatim di folder downloads
      final dir = await _getDownloadDir();
      if (await dir.exists()) {
        final files = dir.listSync();
        for (final f in files) {
          if (f is File && f.lengthSync() < 800000) {
            debugPrint('[Download] Menghapus cache download rusak: ${f.path}');
            await f.delete();
          }
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

  /// Mengunduh audio lagu dengan Range-Based Chunked Downloader agar file 100% utuh
  Future<void> downloadVideoNative(
    VideoItem video, {
    required Function(double progress) onProgress,
    required Function(DownloadedTrack track) onComplete,
    required Function(String error) onError,
  }) async {
    _activeCancelTokens[video.videoId] = false;
    RandomAccessFile? raf;
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

      raf = file.openSync(mode: FileMode.write);
      client = http.Client();

      int totalSize = 0;
      int downloadedBytes = 0;
      int retries = 0;

      while (retries < 6) {
        if (_activeCancelTokens[video.videoId] == true) {
          raf.closeSync();
          if (file.existsSync()) file.deleteSync();
          client.close();
          onError('Unduhan dibatalkan');
          return;
        }

        final request = http.Request('GET', Uri.parse(streamUrl));
        request.headers['User-Agent'] =
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
        request.headers['Referer'] = 'https://www.youtube.com/';
        request.headers['Origin'] = 'https://www.youtube.com';

        if (downloadedBytes > 0) {
          request.headers['Range'] = 'bytes=$downloadedBytes-';
        }

        final response = await client.send(request);

        if (response.statusCode != 200 && response.statusCode != 206) {
          throw Exception('Download stream gagal dengan kode HTTP ${response.statusCode}');
        }

        if (totalSize == 0) {
          if (response.headers.containsKey('content-range')) {
            final cr = response.headers['content-range']!;
            final match = RegExp(r'/(\d+)$').firstMatch(cr);
            if (match != null) totalSize = int.parse(match.group(1)!);
          } else if (response.contentLength != null && response.contentLength! > 0) {
            totalSize = response.contentLength!;
          }
        }

        await for (final chunk in response.stream) {
          if (_activeCancelTokens[video.videoId] == true) {
            raf.closeSync();
            if (file.existsSync()) file.deleteSync();
            client.close();
            onError('Unduhan dibatalkan');
            return;
          }
          raf.writeFromSync(chunk);
          downloadedBytes += chunk.length;
          if (totalSize > 0) {
            onProgress((downloadedBytes / totalSize).clamp(0.0, 1.0));
          }
        }

        if (totalSize > 0 && downloadedBytes >= totalSize) {
          // 100% Downloaded successfully!
          break;
        } else if (totalSize == 0 && downloadedBytes > 1000000) {
          // Completed without explicit length header
          break;
        }

        retries++;
        debugPrint('[Download] Melanjutkan unduhan terputus di $downloadedBytes / $totalSize bytes (Percobaan $retries)...');
        await Future.delayed(const Duration(milliseconds: 600));
      }

      raf.flushSync();
      raf.closeSync();
      client.close();

      final finalSize = file.existsSync() ? file.lengthSync() : 0;
      if (finalSize < 800000) {
        if (file.existsSync()) file.deleteSync();
        throw Exception('File unduhan tidak lengkap ($finalSize bytes, minimal 800KB)');
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
      debugPrint('[Download] Sukses tersimpan 100% utuh: $localPath ($finalSize bytes)');
      onComplete(track);
    } catch (e) {
      try { raf?.closeSync(); } catch (_) {}
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
