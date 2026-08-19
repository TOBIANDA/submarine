// lib/services/download_service.dart
import 'dart:async';
import 'dart:io';
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
  final Map<String, StreamSubscription> _activeSubscriptions = {};

  void init() {}

  Future<void> cancelActiveDownload(String videoId) async {
    final sub = _activeSubscriptions[videoId];
    if (sub != null) {
      await sub.cancel();
      _activeSubscriptions.remove(videoId);
      try {
        final dir = await _getDownloadDir();
        for (final ext in ['m4a', 'mp4', 'webm']) {
          final file = File('${dir.path}/$videoId.$ext');
          if (await file.exists()) await file.delete();
        }
      } catch (_) {}
    }
  }

  /// Mendapatkan direktori download yang tersedia
  Future<Directory> _getDownloadDir() async {
    // Prioritas: external storage agar muncul di Android/data
    try {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        final dir = Directory('${extDir.path}/downloads');
        if (!await dir.exists()) await dir.create(recursive: true);
        return dir;
      }
    } catch (_) {}
    // Fallback ke internal app documents
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/downloads');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Mengunduh audio lagu via stream chunk native (menghindari throttling YouTube)
  Future<void> downloadVideoNative(
    VideoItem video, {
    required Function(double progress) onProgress,
    required Function(DownloadedTrack track) onComplete,
    required Function(String error) onError,
  }) async {
    IOSink? fileStream;
    final completer = Completer<void>();
    try {
      debugPrint('[Download] Mulai unduhan: ${video.title}');

      final clientsToTry = [
        [YoutubeApiClient.ios, YoutubeApiClient.tv],
        [YoutubeApiClient.androidVr],
        null,
      ];

      StreamManifest? manifest;
      for (final clients in clientsToTry) {
        try {
          manifest = await _yt.videos.streamsClient
              .getManifest(video.videoId, ytClients: clients);
          if (manifest.audioOnly.isNotEmpty) break;
        } catch (e) {
          debugPrint('[Download] Client gagal, coba berikutnya...');
        }
      }

      if (manifest == null || manifest.audioOnly.isEmpty) {
        throw Exception('Tidak ada stream audio yang tersedia.');
      }

      final streamInfo = manifest.audioOnly.withHighestBitrate();
      final ext = streamInfo.container.name;
      final downloadDir = await _getDownloadDir();
      final localPath = '${downloadDir.path}/${video.videoId}.$ext';
      final file = File(localPath);
      fileStream = file.openWrite();

      final stream = _yt.videos.streamsClient.get(streamInfo);
      final totalBytes = streamInfo.size.totalBytes;
      int downloadedBytes = 0;

      final subscription = stream.listen(
        (data) {
          downloadedBytes += data.length;
          final progress = totalBytes > 0 ? downloadedBytes / totalBytes : 0.0;
          onProgress(progress);
          fileStream?.add(data);
        },
        onDone: () async {
          await fileStream?.flush();
          await fileStream?.close();
          _activeSubscriptions.remove(video.videoId);

          try {
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
            onError(e.toString());
          } finally {
            if (!completer.isCompleted) completer.complete();
          }
        },
        onError: (e) async {
          await fileStream?.close();
          _activeSubscriptions.remove(video.videoId);
          onError(e.toString());
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );

      _activeSubscriptions[video.videoId] = subscription;
      return completer.future;
    } catch (e) {
      await fileStream?.close();
      _activeSubscriptions.remove(video.videoId);
      debugPrint('[Download] Gagal: $e');
      onError(e.toString());
      if (!completer.isCompleted) completer.complete();
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
