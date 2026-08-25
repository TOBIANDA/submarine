// lib/services/player_service.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:path_provider/path_provider.dart';

import '../models/video_item.dart';
import '../models/play_history.dart';
import '../services/db_service.dart';
import '../services/audio_handler.dart';
import '../services/license_service.dart';

enum RepeatMode { none, all, one }

class PlayerService extends ChangeNotifier {
  static PlayerService? _instance;
  PlayerService._();
  factory PlayerService() => _instance ??= PlayerService._();

  static const _extractorChannel = MethodChannel('com.submarine/extractor');

  late BackgroundAudioHandler _audioHandler;
  AudioPlayer get audioPlayer => _audioHandler.player;

  List<VideoItem> _playlist = [];
  int _currentIndex = -1;
  bool _isShuffle = false;
  RepeatMode _repeatMode = RepeatMode.none;
  bool _audioFocusMode = true;
  bool _isLoadingAudio = false;

  // Set of track IDs that have already triggered 70% radio prefetch
  final Set<String> _prefetchedTrackIds = <String>{};
  bool _isPrefetchingRadio = false;

  VoidCallback? onHistoryUpdated;

  List<VideoItem> get playlist => List.unmodifiable(_playlist);
  List<VideoItem> get queue => List.unmodifiable(_playlist);
  int get currentIndex => _currentIndex;
  VideoItem? get currentVideo =>
      (_currentIndex >= 0 && _currentIndex < _playlist.length)
          ? _playlist[_currentIndex]
          : null;

  bool get isPlaying => audioPlayer.playing;
  bool get isLoadingAudio => _isLoadingAudio;
  bool get isShuffled => _isShuffle;
  bool get isShuffle => _isShuffle;
  RepeatMode get repeatMode => _repeatMode;
  bool get audioFocusMode => _audioFocusMode;
  bool get hasNext => _playlist.isNotEmpty;
  bool get hasPrevious => _playlist.isNotEmpty;

  Stream<Duration> get positionStream => audioPlayer.positionStream;
  Stream<Duration?> get durationStream => audioPlayer.durationStream;
  Duration get position => audioPlayer.position;
  Duration? get duration => audioPlayer.duration;

  Future<void> init(BackgroundAudioHandler handler) async {
    _audioHandler = handler;

    audioPlayer.playerStateStream.listen((state) {
      if (state.playing) {
        _isLoadingAudio = false;
      }
      notifyListeners();
    });

    audioPlayer.playbackEventStream.listen((event) {}, onError: (e) {
      debugPrint('[Player] Player error event: $e');
      _isLoadingAudio = false;
      notifyListeners();
    });

    audioPlayer.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _recordCompletion(1.0);
        _onTrackEnded();
      }
      notifyListeners();
    });

    // ── Pre-fetch Automix at 70% song duration for zero-lag continuous listening ──
    audioPlayer.positionStream.listen((pos) {
      final cur = currentVideo;
      final dur = audioPlayer.duration;
      if (cur != null && dur != null && dur.inSeconds > 15) {
        final progress = pos.inMilliseconds / dur.inMilliseconds;
        if (progress >= 0.70 && !_prefetchedTrackIds.contains(cur.videoId)) {
          _prefetchedTrackIds.add(cur.videoId);
          _prefetchRadioTracks(cur.videoId);
        }
      }
    });

    _audioHandler.customEvent.listen((event) {
      if (event == 'skipToNext') playNext();
      if (event == 'skipToPrevious') playPrevious();
      if (event == 'play') play();
      if (event == 'pause') pause();
      if (event == 'stop') {
        _recordCurrentProgress();
        _playlist.clear();
        _currentIndex = -1;
        _isLoadingAudio = false;
        notifyListeners();
      }
    });
  }

  /// Prefetch 5 related/automix radio tracks from YouTube Music when queue is low
  Future<void> _prefetchRadioTracks(String seedVideoId) async {
    if (_isPrefetchingRadio) return;
    
    // Only prefetch if we are at or near the end of the current playlist
    final remainingInQueue = _playlist.length - 1 - _currentIndex;
    if (remainingInQueue > 2) return;

    _isPrefetchingRadio = true;
    try {
      debugPrint('[Player] Pre-fetching Automix radio tracks for seed: $seedVideoId (progress >= 70%)');
      final List? results = await _extractorChannel.invokeMethod<List>('getRadioTracks', {
        'videoId': seedVideoId,
        'limit': 5,
      });

      if (results != null && results.isNotEmpty) {
        final existingIds = _playlist.map((e) => e.videoId).toSet();
        final newTracks = <VideoItem>[];

        for (final item in results) {
          if (item is Map) {
            final vId = item['videoId'] as String? ?? '';
            if (vId.isNotEmpty && !existingIds.contains(vId)) {
              newTracks.add(VideoItem(
                videoId: vId,
                title: item['title'] as String? ?? 'Unknown Title',
                channelTitle: item['channelTitle'] as String? ?? 'Unknown Artist',
                thumbnailUrl: item['thumbnailUrl'] as String? ?? 'https://i.ytimg.com/vi/$vId/hqdefault.jpg',
                durationSeconds: item['durationSeconds'] as int? ?? 0,
              ));
              existingIds.add(vId);
            }
          }
        }

        if (newTracks.isNotEmpty) {
          _playlist.addAll(newTracks);
          debugPrint('[Player] Added ${newTracks.length} continuous radio tracks to queue!');
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[Player] Pre-fetch radio error (non-fatal): $e');
    } finally {
      _isPrefetchingRadio = false;
    }
  }

  void _recordCompletion(double rate) {
    final cur = currentVideo;
    if (cur != null) {
      DbService().updatePlaybackCompletion(cur.videoId, rate, position.inSeconds);
    }
  }

  void _recordCurrentProgress() {
    final cur = currentVideo;
    final dur = audioPlayer.duration;
    if (cur != null && dur != null && dur.inSeconds > 0) {
      final rate = (position.inSeconds / dur.inSeconds).clamp(0.0, 1.0);
      DbService().updatePlaybackCompletion(cur.videoId, rate, position.inSeconds);
    }
  }

  Future<void> loadQueue(List<VideoItem> items, {int startIndex = 0, int? initialIndex, String? playlistId}) async {
    if (items.isEmpty) return;
    _recordCurrentProgress();
    _playlist = List.from(items);
    final targetIdx = initialIndex ?? startIndex;
    _currentIndex = targetIdx.clamp(0, _playlist.length - 1);
    notifyListeners();
    await _playCurrent();
  }

  void addToQueue(VideoItem item) {
    _playlist.add(item);
    notifyListeners();
  }

  Future<void> playPlaylist(List<VideoItem> videos, {int initialIndex = 0, int startIndex = 0, String? playlistId}) async {
    await loadQueue(videos, initialIndex: initialIndex, startIndex: startIndex, playlistId: playlistId);
  }

  Future<void> playSingle(VideoItem video) async {
    _recordCurrentProgress();
    final idx = _playlist.indexWhere((v) => v.videoId == video.videoId);
    if (idx != -1) {
      _currentIndex = idx;
    } else {
      _playlist.insert(0, video);
      _currentIndex = 0;
    }
    notifyListeners();
    await _playCurrent();
  }

  Future<void> playAt(int index) async {
    if (index >= 0 && index < _playlist.length) {
      _recordCurrentProgress();
      _currentIndex = index;
      notifyListeners();
      await _playCurrent();
    }
  }

  Future<void> _playCurrent() async {
    if (!await LicenseService().isActivated()) {
      debugPrint('[Security] Playback blocked: License not active.');
      await stop();
      return;
    }
    final video = currentVideo;
    if (video == null) return;

    _isLoadingAudio = true;
    notifyListeners();

    try {
      final mediaItem = MediaItem(
        id: video.videoId,
        album: 'Submarine Music',
        title: video.title,
        artist: video.channelTitle,
        artUri: Uri.parse(video.thumbnailUrl),
        duration: video.durationSeconds != null ? Duration(seconds: video.durationSeconds!) : null,
      );

      // Check if downloaded offline
      final offlinePath = await _getOfflineFilePath(video.videoId);
      if (offlinePath != null && await File(offlinePath).exists()) {
        debugPrint('[Player] Playing offline downloaded track: $offlinePath');
        await _audioHandler.playFile(offlinePath, mediaItem);
      } else {
        // Stream online natively via NewPipeExtractor
        debugPrint('[Player] Playing online native stream via NewPipeExtractor for: ${video.title}');
        await _audioHandler.playOnline(video.videoId, mediaItem);
      }

      await DbService().upsertHistory(PlayHistory(
        videoId: video.videoId,
        title: video.title,
        channelTitle: video.channelTitle,
        thumbnailUrl: video.thumbnailUrl,
        playedAt: DateTime.now(),
        durationSeconds: video.durationSeconds ?? 0,
        lastPositionSeconds: 0,
        completionRate: 1.0,
      ));
      onHistoryUpdated?.call();
    } catch (e) {
      debugPrint('[Player] Error playing track ${video.title}: $e');
    } finally {
      _isLoadingAudio = false;
      notifyListeners();
    }
  }

  Future<String?> _getOfflineFilePath(String videoId) async {
    try {
      final downloaded = await DbService().getDownload(videoId);
      if (downloaded != null) {
        final f = File(downloaded.localPath);
        if (await f.exists()) {
          final size = await f.length();
          // Minimal 800KB for complete audio file
          if (size >= 800000) {
            return downloaded.localPath;
          } else {
            debugPrint('[Player] Incomplete offline file ($size bytes). Deleting: ${downloaded.title}');
            await f.delete();
            await DbService().deleteDownload(videoId);
          }
        }
      }
    } catch (e) {
      debugPrint('[Player] Error resolving offline file path: $e');
    }
    return null;
  }

  Future<void> play() async => audioPlayer.play();
  Future<void> pause() async => audioPlayer.pause();
  Future<void> togglePlay() async {
    if (isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seek(Duration pos) async => audioPlayer.seek(pos);
  Future<void> seekTo(Duration pos) async => audioPlayer.seek(pos);

  Future<void> playNext() async {
    if (_playlist.isEmpty) return;
    _recordCurrentProgress();
    if (_isShuffle) {
      _currentIndex = (DateTime.now().millisecondsSinceEpoch % _playlist.length);
    } else {
      _currentIndex = (_currentIndex + 1) % _playlist.length;
    }
    notifyListeners();
    await _playCurrent();
  }

  Future<void> playPrevious() async {
    if (_playlist.isEmpty) return;
    _recordCurrentProgress();
    if (_currentIndex > 0) {
      _currentIndex--;
    } else {
      _currentIndex = _playlist.length - 1;
    }
    notifyListeners();
    await _playCurrent();
  }

  Future<void> stop() async {
    _recordCurrentProgress();
    try {
      await _audioHandler.stop();
    } catch (_) {}
    _playlist.clear();
    _currentIndex = -1;
    _isLoadingAudio = false;
    notifyListeners();
  }

  void toggleShuffle() {
    _isShuffle = !_isShuffle;
    notifyListeners();
  }

  void cycleRepeatMode() {
    _repeatMode = switch (_repeatMode) {
      RepeatMode.none => RepeatMode.all,
      RepeatMode.all  => RepeatMode.one,
      RepeatMode.one  => RepeatMode.none,
    };
    final justAudioMode = switch (_repeatMode) {
      RepeatMode.none => LoopMode.off,
      RepeatMode.all  => LoopMode.all,
      RepeatMode.one  => LoopMode.one,
    };
    audioPlayer.setLoopMode(justAudioMode);
    notifyListeners();
  }

  void toggleAudioFocus() {
    _audioFocusMode = !_audioFocusMode;
    notifyListeners();
  }

  void _onTrackEnded() {
    if (_repeatMode == RepeatMode.one) {
      _playCurrent();
    } else if (_playlist.isNotEmpty) {
      // Seamlessly loop from tail back to head
      playNext();
    }
  }
}
