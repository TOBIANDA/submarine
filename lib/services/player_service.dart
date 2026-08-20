import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../models/video_item.dart';
import '../models/play_history.dart';
import 'audio_handler.dart';
import 'db_service.dart';
import 'youtube_service.dart';
import 'ai_service.dart';

export 'package:just_audio/just_audio.dart' show AudioPlayer, ProcessingState;

enum RepeatMode { none, all, one }

class PlayerService extends ChangeNotifier {
  static PlayerService? _instance;
  PlayerService._();
  factory PlayerService() => _instance ??= PlayerService._();

  BackgroundAudioHandler? _audioHandler;
  final YoutubeExplode _yt = YoutubeExplode();
  YoutubePlayerController? _ytController;

  // ─── State ─────────────────────────────────
  VideoItem? _currentVideo;
  List<VideoItem> _queue = [];
  int _currentIndex = -1;
  bool _isPlaying = false;
  bool _isShuffled = false;
  RepeatMode _repeatMode = RepeatMode.none;
  bool _audioFocusMode = false;
  String? _currentPlaylistId;
  bool _isLoadingAudio = false;
  bool _isPlayingOffline = false;

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

  YoutubePlayerController get youtubeController {
    return _ytController ??= YoutubePlayerController(
      initialVideoId: '',
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: false,
        disableDragSeek: false,
        loop: false,
        isLive: false,
        forceHD: false,
        enableCaption: false,
        showLiveFullscreenButton: false,
      ),
    )..addListener(_onYoutubePlayerChanged);
  }

  void _onYoutubePlayerChanged() {
    if (_ytController == null || _isPlayingOffline) return;
    final value = _ytController!.value;

    _currentPosition = value.position;
    _positionController.add(_currentPosition);

    if (value.metaData.duration > Duration.zero) {
      _currentDuration = value.metaData.duration;
      _durationController.add(_currentDuration);

      final curItem = _audioHandler?.mediaItem.value;
      if (curItem != null && curItem.duration != _currentDuration) {
        _audioHandler?.mediaItem.add(curItem.copyWith(duration: _currentDuration));
      }
    }

    final playing = value.isPlaying;
    if (_isPlaying != playing) {
      _isPlaying = playing;
      _audioHandler?.playbackState.add(
        _audioHandler!.playbackState.value.copyWith(
          playing: playing,
          processingState: AudioProcessingState.ready,
        ),
      );
      notifyListeners();
    }

    if (value.playerState == PlayerState.ended) {
      playNext();
    }
  }

  // ─── Init ──────────────────────────────────
  void init(BackgroundAudioHandler handler) {
    _audioHandler = handler;

    // Listen to playback state from offline audio_service
    handler.playbackState.listen((state) {
      if (_isPlayingOffline) {
        final playing = state.playing;
        if (_isPlaying != playing) {
          _isPlaying = playing;
          notifyListeners();
        }
      }
    });

    handler.player.positionStream.listen((pos) {
      if (_isPlayingOffline) {
        _currentPosition = pos;
        _positionController.add(pos);
      }
    });

    handler.player.durationStream.listen((dur) {
      if (_isPlayingOffline) {
        _currentDuration = dur;
        _durationController.add(dur);
      }
    });

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
  bool get audioFocusMode => _audioFocusMode;
  String? get currentPlaylistId => _currentPlaylistId;
  bool get hasNext => _queue.isNotEmpty && (_currentIndex < _queue.length - 1 || _repeatMode == RepeatMode.all || _isShuffled);
  bool get hasPrevious => _queue.isNotEmpty && (_currentIndex > 0 || _isShuffled);
  bool get isLoadingAudio => _isLoadingAudio;
  AudioPlayer? get audioPlayer => _audioHandler?.player;

  Duration get position => _currentPosition;
  Duration? get duration => _currentDuration ?? (_currentVideo != null && _currentVideo!.durationSeconds > 0 ? Duration(seconds: _currentVideo!.durationSeconds) : null);
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration?> get durationStream => _durationController.stream;

  // ─── Playback Control ──────────────────────

  void loadQueue(List<VideoItem> items, {int startIndex = 0, String? playlistId}) {
    _queue = List.from(items);
    _currentPlaylistId = playlistId;
    _shuffleHistory = [];
    _unplayedShuffleIndices = [];
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
    _consecutiveSuggestFailures = 0;
    notifyListeners();
    _saveToHistory(video);
    _loadAndPlayAudio(video);
  }

  void playAt(int index) {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    _currentVideo = _queue[index];
    notifyListeners();
    _saveToHistory(_currentVideo!);
    _loadAndPlayAudio(_currentVideo!);
  }

  void playNext() {
    if (_queue.isEmpty) return;

    if (_repeatMode == RepeatMode.one && _currentVideo != null) {
      seek(Duration.zero);
      if (!_isPlaying) togglePlay();
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
    } else if (_repeatMode == RepeatMode.all) {
      playAt(0);
    } else {
      _autoSuggestAndPlayNext();
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

  int _consecutiveSuggestFailures = 0;

  Future<void> _autoSuggestAndPlayNext() async {
    if (_currentVideo == null) return;
    if (_consecutiveSuggestFailures >= 3) {
      debugPrint('[Player] Terlalu banyak kegagalan auto-suggest, hentikan autoplay.');
      _isPlaying = false;
      notifyListeners();
      return;
    }

    try {
      _isLoadingAudio = true;
      notifyListeners();

      List<VideoItem> candidates = [];
      try {
        final aiSuggestion = await AiService().recommendNextSong(
          _currentVideo!.title,
          _currentVideo!.channelTitle,
        );

        if (aiSuggestion != null && aiSuggestion.isNotEmpty) {
          final aiResults = await YoutubeService().searchVideos(aiSuggestion, maxResults: 5);
          if (aiResults.isNotEmpty) {
            candidates.addAll(aiResults);
          }
        }
      } catch (e) {
        debugPrint('[Player] AI Suggest error: $e');
      }

      if (candidates.isEmpty) {
        final related = await YoutubeService().getRelatedVideos(_currentVideo!);
        candidates.addAll(related);
      }

      final existingIds = _queue.map((v) => v.videoId).toSet();
      final filtered = candidates.where((v) => !existingIds.contains(v.videoId)).toList();

      if (filtered.isNotEmpty) {
        final bestCandidate = filtered.first;
        addToQueue(bestCandidate);
        playAt(_queue.length - 1);
        _consecutiveSuggestFailures = 0;
      } else {
        _isPlaying = false;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[Player] Gagal auto-queue lagu baru: $e');
      _consecutiveSuggestFailures++;
      _isPlaying = false;
      notifyListeners();
    } finally {
      if (_isLoadingAudio) {
        _isLoadingAudio = false;
        notifyListeners();
      }
    }
  }

  void stop() {
    _currentVideo = null;
    _currentIndex = -1;
    _isPlaying = false;
    _isPlayingOffline = false;
    if (_ytController != null) {
      _ytController!.pause();
      _ytController!.cue('');
    }
    _audioHandler?.stop();
    notifyListeners();
  }

  void togglePlay() {
    if (_isPlayingOffline) {
      if (_isPlaying) {
        _audioHandler?.pause();
      } else {
        _audioHandler?.play();
      }
    } else {
      if (_isPlaying) {
        youtubeController.pause();
        _isPlaying = false;
      } else {
        youtubeController.play();
        _isPlaying = true;
      }
      notifyListeners();
    }
  }

  void setPlaying(bool playing) {
    if (_isPlaying != playing) {
      _isPlaying = playing;
      notifyListeners();
    }
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
    if (_isPlayingOffline) {
      _audioHandler?.player.seek(position);
    } else {
      youtubeController.seekTo(position);
    }
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

  void toggleAudioFocusMode() {
    _audioFocusMode = !_audioFocusMode;
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
    notifyListeners();

    try {
      // 1. Cek apakah ada file offline yang valid
      final downloaded = await DbService().getDownload(video.videoId);
      bool playedOffline = false;

      if (downloaded != null && File(downloaded.localPath).existsSync() && File(downloaded.localPath).lengthSync() > 50000) {
        debugPrint('[Player] 🎵 Memutar dari file offline valid: ${downloaded.localPath}');
        final mediaItem = _buildMediaItem(video);
        if (_loadId != currentLoadId) return;
        try {
          if (_ytController != null) {
            _ytController!.pause();
            _ytController!.cue('');
          }
          await _audioHandler!.loadUrl(downloaded.localPath, mediaItem);
          if (_loadId != currentLoadId) return;

          _audioHandler!.play();
          _isPlayingOffline = true;
          playedOffline = true;
          _isPlaying = true;
        } catch (e) {
          debugPrint('[Player] Offline file load failed, fallback to YouTube: $e');
          playedOffline = false;
        }
      }

      if (!playedOffline) {
        if (_loadId != currentLoadId) return;
        _isPlayingOffline = false;
        await _audioHandler!.player.stop();

        final mediaItem = _buildMediaItem(video);
        _audioHandler!.mediaItem.add(mediaItem);
        _audioHandler!.playbackState.add(
          _audioHandler!.playbackState.value.copyWith(
            processingState: AudioProcessingState.ready,
            playing: true,
          ),
        );

        debugPrint('[Player] 🚀 Loading YouTube Video via Official Player: ${video.title} (${video.videoId})');
        youtubeController.load(video.videoId);
        _isPlaying = true;
      }
    } catch (e) {
      debugPrint('[Player] AudioLoad error: $e');
      _isPlaying = false;
      _currentVideo = null;
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
      artUri: video.thumbnailUrl.isNotEmpty
          ? Uri.parse(video.thumbnailUrl)
          : null,
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
    _ytController?.dispose();
    _yt.close();
    super.dispose();
  }
}
