// lib/services/player_service.dart
import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'youtube_stream_source.dart';

import '../models/video_item.dart';
import '../models/play_history.dart';
import 'audio_handler.dart';
import 'db_service.dart';

export 'package:just_audio/just_audio.dart' show AudioPlayer, ProcessingState;

enum RepeatMode { none, all, one }

class PlayerService extends ChangeNotifier {
  static PlayerService? _instance;
  PlayerService._();
  factory PlayerService() => _instance ??= PlayerService._();

  BackgroundAudioHandler? _audioHandler;
  final YoutubeExplode _yt = YoutubeExplode();

  // ─── State ─────────────────────────────────
  VideoItem? _currentVideo;
  List<VideoItem> _queue = [];
  int _currentIndex = -1;
  bool _isPlaying = false;
  bool _isShuffled = false;
  RepeatMode _repeatMode = RepeatMode.none;
  String? _currentPlaylistId;
  bool _isLoadingAudio = false;
  bool _hasPlayedCurrentSong = false;

  Duration _currentPosition = Duration.zero;
  Duration? _currentDuration;
  final StreamController<Duration> _positionController = StreamController<Duration>.broadcast();
  final StreamController<Duration?> _durationController = StreamController<Duration?>.broadcast();

  // Shuffle queue state
  List<int> _shuffleHistory = [];
  List<int> _unplayedShuffleIndices = [];

  // Cancellation token for overlapping loads
  int _loadId = 0;

  // Callback to invalidate history provider
  VoidCallback? onHistoryUpdated;

  // ─── Init ──────────────────────────────────
  void init(BackgroundAudioHandler handler) {
    _audioHandler = handler;

    handler.player.playerStateStream.listen((state) {
      final playing = state.playing;
      if (_isPlaying != playing) {
        _isPlaying = playing;
        notifyListeners();
      }

      // Auto-advance: track completed naturally
      if (state.processingState == ProcessingState.completed && _hasPlayedCurrentSong) {
        debugPrint('[Player] Track ended naturally, advancing...');
        _hasPlayedCurrentSong = false;
        playNext();
      }
    });

    handler.player.positionStream.listen((pos) {
      _currentPosition = pos;
      _positionController.add(pos);
      if (pos.inSeconds >= 4) {
        _hasPlayedCurrentSong = true;
      }
    });

    handler.player.durationStream.listen((dur) {
      if (dur != null && dur > Duration.zero) {
        _currentDuration = dur;
        _durationController.add(dur);
        // Update media item with actual duration
        final curItem = handler.mediaItem.value;
        if (curItem != null && curItem.duration != dur) {
          handler.updateMediaItem(curItem.copyWith(duration: dur));
        }
      }
    });

    // Handle media button commands (lockscreen / headphone)
    handler.customEvent.listen((event) {
      if (event == 'skipToNext') {
        playNext();
      } else if (event == 'skipToPrevious') {
        playPrevious();
      }
    });
  }

  // ─── Getters ───────────────────────────────
  VideoItem? get currentVideo => _currentVideo;
  List<VideoItem> get queue => _queue;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  bool get isShuffled => _isShuffled;
  RepeatMode get repeatMode => _repeatMode;
  String? get currentPlaylistId => _currentPlaylistId;
  bool get hasNext => _queue.isNotEmpty;
  bool get hasPrevious => _queue.isNotEmpty && _currentIndex > 0;
  bool get isLoadingAudio => _isLoadingAudio;
  AudioPlayer? get audioPlayer => _audioHandler?.player;

  Duration get position => _currentPosition;
  Duration? get duration => _currentDuration ?? (_currentVideo != null && _currentVideo!.durationSeconds > 0
      ? Duration(seconds: _currentVideo!.durationSeconds)
      : null);
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration?> get durationStream => _durationController.stream;

  // ─── Playback Control ──────────────────────

  void loadQueue(List<VideoItem> items, {int startIndex = 0, String? playlistId}) {
    _queue = List.from(items);
    _currentPlaylistId = playlistId;
    _initShuffleIndices();
    if (startIndex >= 0 && startIndex < _queue.length) {
      playAt(startIndex);
    }
  }

  void playSingle(VideoItem video) {
    _queue = [video];
    _currentPlaylistId = null;
    playAt(0);
  }

  void playVideo(VideoItem video, {List<VideoItem>? queue, int? index, String? playlistId}) {
    if (queue != null) {
      _queue = List.from(queue);
      _currentIndex = index ?? 0;
      _currentPlaylistId = playlistId;
      _initShuffleIndices();
    } else if (!_queue.any((v) => v.videoId == video.videoId)) {
      _queue.add(video);
      _currentIndex = _queue.length - 1;
      _initShuffleIndices();
    } else {
      _currentIndex = _queue.indexWhere((v) => v.videoId == video.videoId);
    }

    _currentVideo = video;
    _hasPlayedCurrentSong = false;
    notifyListeners();
    _saveToHistory(video);
    _loadAndPlayAudio(video);
  }

  void playAt(int index) {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    _currentVideo = _queue[index];
    _hasPlayedCurrentSong = false;
    notifyListeners();
    _saveToHistory(_currentVideo!);
    _loadAndPlayAudio(_currentVideo!);
  }

  void playNext() {
    if (_queue.isEmpty) return;

    if (_repeatMode == RepeatMode.one && _currentVideo != null) {
      seek(Duration.zero);
      _audioHandler?.play();
      return;
    }

    if (_isShuffled) {
      final nextIdx = _getNextShuffleIndex();
      if (nextIdx != null) {
        playAt(nextIdx);
        return;
      }
    }

    if (_currentIndex < _queue.length - 1) {
      playAt(_currentIndex + 1);
    } else {
      // Loop back to head
      debugPrint('[Player] Reached end of playlist, looping to head');
      playAt(0);
    }
  }

  void playPrevious() {
    if (_queue.isEmpty) return;

    if (_currentPosition.inSeconds > 3) {
      seek(Duration.zero);
      return;
    }

    if (_isShuffled && _shuffleHistory.length > 1) {
      _shuffleHistory.removeLast();
      final prevIdx = _shuffleHistory.last;
      playAt(prevIdx);
      return;
    }

    if (_currentIndex > 0) {
      playAt(_currentIndex - 1);
    } else {
      seek(Duration.zero);
    }
  }

  void stop() {
    _currentVideo = null;
    _currentIndex = -1;
    _isPlaying = false;
    _hasPlayedCurrentSong = false;
    _currentPosition = Duration.zero;
    _currentDuration = null;
    _audioHandler?.stop();
    notifyListeners();
  }

  void togglePlay() {
    if (_isPlaying) {
      _audioHandler?.pause();
    } else {
      _audioHandler?.play();
    }
    notifyListeners();
  }

  void toggleShuffle() {
    _isShuffled = !_isShuffled;
    _initShuffleIndices();
    notifyListeners();
  }

  void cycleRepeatMode() {
    _repeatMode = switch (_repeatMode) {
      RepeatMode.none => RepeatMode.all,
      RepeatMode.all  => RepeatMode.one,
      RepeatMode.one  => RepeatMode.none,
    };
    notifyListeners();
  }

  void seek(Duration position) {
    _currentPosition = position;
    _positionController.add(position);
    _audioHandler?.seek(position);
    notifyListeners();
  }

  void addToQueue(VideoItem video) {
    _queue.add(video);
    _initShuffleIndices();
    notifyListeners();
  }

  void playNextInQueue(VideoItem video) {
    if (_queue.isEmpty) {
      playVideo(video);
      return;
    }
    _queue.insert(_currentIndex + 1, video);
    _initShuffleIndices();
    notifyListeners();
  }

  void clearQueue() {
    if (_currentVideo != null) {
      _queue = [_currentVideo!];
      _currentIndex = 0;
    } else {
      _queue.clear();
      _currentIndex = -1;
    }
    _initShuffleIndices();
    notifyListeners();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _queue.length ||
        newIndex < 0 || newIndex > _queue.length) return;
    if (oldIndex < newIndex) newIndex -= 1;
    final item = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, item);
    if (oldIndex == _currentIndex) {
      _currentIndex = newIndex;
    } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
      _currentIndex -= 1;
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      _currentIndex += 1;
    }
    _initShuffleIndices();
    notifyListeners();
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= _queue.length) return;
    _queue.removeAt(index);
    if (index < _currentIndex) {
      _currentIndex--;
    } else if (index == _currentIndex) {
      if (_queue.isNotEmpty) {
        playAt(_currentIndex.clamp(0, _queue.length - 1));
      } else {
        stop();
      }
    }
    notifyListeners();
  }

  // ─── Private ───────────────────────────────

  Future<void> _loadAndPlayAudio(VideoItem video) async {
    if (_audioHandler == null) return;

    _loadId++;
    final currentLoadId = _loadId;

    _isLoadingAudio = true;
    _hasPlayedCurrentSong = false;
    _currentPosition = Duration.zero;
    _currentDuration = null;
    _positionController.add(Duration.zero);
    notifyListeners();

    try {
      final mediaItem = _buildMediaItem(video);

      // 1. Try offline file first
      final downloaded = await DbService().getDownload(video.videoId);
      if (downloaded != null &&
          File(downloaded.localPath).existsSync() &&
          File(downloaded.localPath).lengthSync() > 50000) {
        if (_loadId != currentLoadId) return;
        debugPrint('[Player] Playing offline: ${video.title}');
        await _audioHandler!.playFile(downloaded.localPath, mediaItem);
        _isPlaying = true;
        _isLoadingAudio = false;
        notifyListeners();
        return;
      }

      // 2. Extract YouTube audio stream URL via youtube_explode_dart
      if (_loadId != currentLoadId) return;
      debugPrint('[Player] Extracting YouTube audio stream for: ${video.title}');

      StreamManifest manifest;
      try {
        manifest = await _yt.videos.streamsClient
            .getManifest(video.videoId)
            .timeout(const Duration(seconds: 20));
      } catch (e) {
        debugPrint('[Player] Stream manifest failed: $e');
        throw Exception('Gagal mendapatkan stream audio: $e');
      }

      if (_loadId != currentLoadId) return;

      // Pick best audio-only stream (highest bitrate)
      final audioStreams = manifest.audioOnly;
      if (audioStreams.isEmpty) {
        throw Exception('Tidak ada stream audio tersedia untuk video ini');
      }

      final streamInfo = audioStreams.withHighestBitrate();
      debugPrint('[Player] Stream bitrate: ' + streamInfo.bitrate.toString());
      if (_loadId != currentLoadId) return;

      // 3. Download audio to temp file via youtube_explode (bypasses all HTTP issues)
      debugPrint('[Player] Downloading audio stream...');
      final tempPath = await YoutubeStreamDownloader.downloadToTempFile(
        yt: _yt,
        streamInfo: streamInfo,
        videoId: video.videoId,
      );
      
      if (_loadId != currentLoadId) return;

      // 4. Play the downloaded temp file via ExoPlayer
      await _audioHandler!.playFile(tempPath, mediaItem);
      _isPlaying = true;
    } catch (e) {
      debugPrint('[Player] Load error: $e');
      _isPlaying = false;
      notifyListeners();
    } finally {
      _isLoadingAudio = false;
      notifyListeners();
    }
  }

  MediaItem _buildMediaItem(VideoItem video) {
    return MediaItem(
      id: video.videoId,
      title: video.title,
      artist: video.channelTitle,
      duration: video.durationSeconds > 0
          ? Duration(seconds: video.durationSeconds)
          : null,
      artUri: video.thumbnailUrl.isNotEmpty ? Uri.parse(video.thumbnailUrl) : null,
    );
  }

  void _saveToHistory(VideoItem video) {
    DbService().upsertHistory(
      PlayHistory(
        videoId: video.videoId,
        title: video.title,
        channelTitle: video.channelTitle,
        thumbnailUrl: video.thumbnailUrl,
        playedAt: DateTime.now(),
        durationSeconds: video.durationSeconds,
      ),
    );
    onHistoryUpdated?.call();
  }

  void _initShuffleIndices() {
    _shuffleHistory = [_currentIndex];
    _unplayedShuffleIndices = List.generate(_queue.length, (i) => i)
      ..remove(_currentIndex)
      ..shuffle();
  }

  int? _getNextShuffleIndex() {
    if (_unplayedShuffleIndices.isEmpty) {
      if (_repeatMode == RepeatMode.all) {
        _initShuffleIndices();
      } else {
        return null;
      }
    }
    final next = _unplayedShuffleIndices.removeAt(0);
    _shuffleHistory.add(next);
    return next;
  }

  @override
  void dispose() {
    _positionController.close();
    _durationController.close();
    _yt.close();
    super.dispose();
  }
}


