// lib/providers/download_provider.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart'; // Untuk mendapatkan scaffoldMessengerKey
import '../models/downloaded_track.dart';
import '../models/video_item.dart';
import '../services/db_service.dart';
import '../services/download_service.dart';

class ActiveDownload {
  final VideoItem video;
  final double progress;
  final bool isWaiting;
  final String taskId;

  ActiveDownload({
    required this.video,
    required this.progress,
    required this.taskId,
    this.isWaiting = false,
  });

  ActiveDownload copyWith({
    VideoItem? video,
    double? progress,
    bool? isWaiting,
    String? taskId,
  }) {
    return ActiveDownload(
      video: video ?? this.video,
      progress: progress ?? this.progress,
      isWaiting: isWaiting ?? this.isWaiting,
      taskId: taskId ?? this.taskId,
    );
  }
}

// Provider untuk memantau status download yang sedang berjalan
// Key: videoId, Value: ActiveDownload
final activeDownloadsProvider =
    StateNotifierProvider<ActiveDownloadsNotifier, Map<String, ActiveDownload>>((ref) {
  return ActiveDownloadsNotifier(ref);
});

class ActiveDownloadsNotifier extends StateNotifier<Map<String, ActiveDownload>> {
  final Ref ref;
  
  final List<VideoItem> _downloadQueue = [];
  bool _isProcessingQueue = false;

  ActiveDownloadsNotifier(this.ref) : super({}) {
    _init();
  }

  void _init() async {
    DownloadService().init();
  }

  void downloadAll(List<VideoItem> videos) async {
    final downloadedTracks = await ref.read(downloadedTracksProvider.future);
    final downloadedIds = downloadedTracks.map((t) => t.videoId).toSet();

    final toDownload = videos.where((v) => 
      !state.containsKey(v.videoId) && !downloadedIds.contains(v.videoId)
    ).toList();

    if (toDownload.isNotEmpty) {
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('Menambahkan ${toDownload.length} lagu ke antrean...'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      final newState = Map<String, ActiveDownload>.from(state);
      for (var video in toDownload) {
        newState[video.videoId] = ActiveDownload(
          video: video, 
          progress: 0.0, 
          isWaiting: true,
          taskId: video.videoId,
        );
        _downloadQueue.add(video);
      }
      state = newState;
      
      _processQueue();

    } else {
      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Semua lagu sudah diunduh atau ada di antrean.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> startDownload(VideoItem video, {bool showSnackbar = true}) async {
    if (state.containsKey(video.videoId)) return;

    final isDownloaded = await ref.read(isDownloadedProvider(video.videoId).future);
    if (isDownloaded) {
      if (showSnackbar) {
        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text('Lagu ini sudah diunduh.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    if (showSnackbar) {
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('Mengantre: ${video.title}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    // Set state awal
    state = {
      ...state,
      video.videoId: ActiveDownload(
        video: video, 
        progress: 0.0, 
        isWaiting: true,
        taskId: video.videoId,
      ),
    };

    _downloadQueue.add(video);
    _processQueue();
  }

  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    while (_downloadQueue.isNotEmpty) {
      final video = _downloadQueue.removeAt(0);

      // Jika user membatalkan antrean sebelum dimulai, videoId tidak ada di state lagi
      if (!state.containsKey(video.videoId)) continue;

      try {
        await DownloadService().downloadVideoNative(
          video,
          onProgress: (progress) {
            final current = state[video.videoId];
            if (current != null) {
              state = {
                ...state,
                video.videoId: current.copyWith(
                  progress: progress,
                  isWaiting: false,
                ),
              };
            }
          },
          onComplete: (track) {
            scaffoldMessengerKey.currentState?.showSnackBar(
              SnackBar(
                content: Text('Berhasil mengunduh: ${video.title}'),
                backgroundColor: Colors.green.shade800,
                behavior: SnackBarBehavior.floating,
              ),
            );
            
            final newState = Map<String, ActiveDownload>.from(state);
            newState.remove(video.videoId);
            state = newState;

            ref.invalidate(downloadedTracksProvider);
          },
          onError: (error) {
            scaffoldMessengerKey.currentState?.showSnackBar(
              SnackBar(
                content: Text('Gagal mengunduh: ${video.title}'),
                backgroundColor: Colors.red.shade800,
                behavior: SnackBarBehavior.floating,
              ),
            );
            final newState = Map<String, ActiveDownload>.from(state);
            newState.remove(video.videoId);
            state = newState;
          },
        );
      } catch (e) {
        final newState = Map<String, ActiveDownload>.from(state);
        newState.remove(video.videoId);
        state = newState;

        scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text('❌ Gagal mengantrekan: ${video.title}'),
            backgroundColor: Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      
      // Jeda 1 detik antar unduhan untuk menghindari rate limit YouTube
      await Future.delayed(const Duration(milliseconds: 1000));
    }

    _isProcessingQueue = false;
  }

  Future<void> cancelDownload(String videoId) async {
    final download = state[videoId];
    if (download != null) {
      await DownloadService().cancelActiveDownload(videoId);
      
      final newState = Map<String, ActiveDownload>.from(state);
      newState.remove(videoId);
      state = newState;

      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('Batal mengunduh: ${download.video.title}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

// Provider untuk mengambil daftar track yang sudah selesai diunduh dari database
final downloadedTracksProvider = FutureProvider<List<DownloadedTrack>>((ref) async {
  return DbService().getAllDownloads();
});

// Provider untuk mengecek apakah sebuah video spesifik sudah didownload
final isDownloadedProvider =
    FutureProvider.family<bool, String>((ref, videoId) async {
  final tracks = await ref.watch(downloadedTracksProvider.future);
  return tracks.any((t) => t.videoId == videoId);
});
