// lib/services/player_service.dart
import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../models/video_item.dart';
import '../models/play_history.dart';
import 'audio_handler.dart';
import 'db_service.dart';
import 'stream_proxy_server.dart';

export 'package:just_audio/just_audio.dart' show AudioPlayer, ProcessingState;

enum RepeatMode { none, all, one }

class PlayerService extends ChangeNotifier {
  static PlayerService? _instance;
  PlayerService._();
  factory PlayerService() => _instance ??= PlayerService._();

  BackgroundAudioHandler? _audioHandler;

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

  // Legacy controller getter (for backward compatibility if needed)
  YoutubePlayerController? _dummyYtController;
  YoutubePlayerController get youtubeController => _dummyYtController ??= YoutubePlayerController(initialVideoId: '');

  // ─── Init ──────────────────────────────────
  void init(BackgroundAudioHandler handler) {
    _audioHandler = handler;

    // Start local stream proxy server
    StreamProxyServer().start();

    // Listen to playback state from audio_service
    handler.playbackState.listen((state) {
      final playing = state.playing;
      if (_isPlaying != playing) {
        _isPlaying = playing;
        notifyListeners();
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
      }
    });

    handler.player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed && _hasPlayedCurrentSong) {
        debugPrint('[Player] Track ended naturally, playing next...');
        _hasPlayedCurrentSong = false;
        playNext();
      }
    });

    // Listen to notification media button events
    handler.customEvent.listen((event) {
      if (event == 'skipToNext') playNext();
      if (event == 'skipToPrevious') playPrevious();
    });
  }

  // ─── Getters ───────────────────────────────
  VideoItem? get currentVideo => _currentVideo;
  List<VideoItem> get queue => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  bool get isShuffled => _isShuffled;
  RepeatMode get repeatMode => _repeatMode;
  bool get audioFocusMode => _audioFocusMode;
  String? get currentPlaylistId => _currentPlaylistId;
  Duration get currentPosition => _currentPosition;
  Duration? get currentDuration => _currentDuration;
  Duration? get duration => _currentDuration ?? (_currentVideo != null && _currentVideo!.durationSeconds > 0 ? Duration(seconds: _currentVideo!.durationSeconds) : null);
  AudioPlayer? get audioPlayer => _audioHandler?.player;
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration?> get durationStream => _durationController.stream;
  bool get hasNext => _queue.isNotEmpty && (_isShuffled || _currentIndex < _queue.length - 1);
  bool get hasPrevious => _queue.isNotEmpty && (_isShuffled ? _shuffleHistory.length > 1 : _currentIndex > 0);
  bool get isLoadingAudio => _isLoadingAudio;
  bool get isPlayingOffline => _isPlayingOffline;

  // ─── Playback Controls ─────────────────────

  void playSingle(VideoItem video) {
    playVideo(video);
  }

  void loadQueue(List<VideoItem> items, {int startIndex = 0, String? playlistId}) {
    playPlaylist(songs: items, initialIndex: startIndex, playlistId: playlistId);
  }

  Future<void> playVideo(VideoItem video) async {
    _currentPlaylistId = null;
    _queue = [video];
    _currentIndex = 0;
    _shuffleHistory = [0];
    _unplayedShuffleIndices = [];
    _currentPosition = Duration.zero;
    _currentDuration = video.durationSeconds > 0 ? Duration(seconds: video.durationSeconds) : null;
    _currentVideo = video;
    _hasPlayedCurrentSong = false;
    notifyListeners();
    _saveToHistory(video);
    await _loadAndPlayAudio(video);
  }

  Future<void> playPlaylist({
    required List<VideoItem> songs,
    int initialIndex = 0,
    String? playlistId,
  }) async {
    if (songs.isEmpty) return;
    _currentPlaylistId = playlistId;
    _queue = List.from(songs);
    _currentIndex = initialIndex.clamp(0, _queue.length - 1);
    _initShuffleIndices();
    final video = _queue[_currentIndex];
    _currentPosition = Duration.zero;
    _currentDuration = video.durationSeconds > 0 ? Duration(seconds: video.durationSeconds) : null;
    _currentVideo = video;
    _hasPlayedCurrentSong = false;
    notifyListeners();
    _saveToHistory(video);
    await _loadAndPlayAudio(video);
  }

  void playAt(int index) {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    if (_isShuffled) {
      _shuffleHistory.add(index);
      _unplayedShuffleIndices.remove(index);
    }
    _currentVideo = _queue[_currentIndex];
    _currentPosition = Duration.zero;
    _currentDuration = _currentVideo!.durationSeconds > 0
        ? Duration(seconds: _currentVideo!.durationSeconds)
        : null;
    _hasPlayedCurrentSong = false;
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
    } else {
      debugPrint('[Player] Reached tail of playlist, looping back to head (index 0)');
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
    _isPlayingOffline = false;
    _hasPlayedCurrentSong = false;
    _audioHandler?.stop();
    notifyListeners();
  }

  void togglePlay() {
    if (_isPlaying) {
      _audioHandler?.pause();
      _isPlaying = false;
    } else {
      _audioHandler?.play();
      _isPlaying = true;
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
    _hasPlayedCurrentSong = false;
    notifyListeners();

    try {
      final mediaItem = _buildMediaItem(video);

      // 1. Cek file offline lokal
      final downloaded = await DbService().getDownload(video.videoId);
      if (downloaded != null && File(downloaded.localPath).existsSync() && File(downloaded.localPath).lengthSync() > 50000) {
        debugPrint('[Player] Memutar dari file offline: ${downloaded.localPath}');
        if (_loadId != currentLoadId) return;
        _isPlayingOffline = true;
        await _audioHandler!.playFile(downloaded.localPath, mediaItem);
        _isPlaying = true;
        _isLoadingAudio = false;
        notifyListeners();
        return;
      }

      // 2. Stream online via Local Proxy + ExoPlayer
      if (_loadId != currentLoadId) return;
      _isPlayingOffline = false;

      final proxyUrl = StreamProxyServer().getStreamUrl(video.videoId);
      debugPrint('[Player] Playing online stream via Local Proxy: $proxyUrl');
      await _audioHandler!.playStreamUrl(proxyUrl, mediaItem);
      _isPlaying = true;
    } catch (e) {
      debugPrint('[Player] AudioLoad error: $e');
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
      artUri: video.thumbnailUrl.isNotEmpty
          ? Uri.tryParse(video.thumbnailUrl)
          : null,
    );
  }

  void _saveToHistory(VideoItem video) {
    DbService().upsertHistory(PlayHistory(
      videoId: video.videoId,
      title: video.title,
      channelTitle: video.channelTitle,
      thumbnailUrl: video.thumbnailUrl,
      durationSeconds: video.durationSeconds,
      playedAt: DateTime.now(),
    )).then((_) {
      onHistoryUpdated?.call();
    });
  }

  void _initShuffleIndices() {
    _unplayedShuffleIndices = List.generate(_queue.length, (i) => i);
    _unplayedShuffleIndices.remove(_currentIndex);
    _shuffleHistory = [_currentIndex];
  }

  int? _getNextShuffleIndex() {
    if (_unplayedShuffleIndices.isEmpty) {
      if (_repeatMode == RepeatMode.all) {
        _initShuffleIndices();
      } else {
        return null;
      }
    }
    _unplayedShuffleIndices.shuffle();
    return _unplayedShuffleIndices.first;
  }

  @override
  void dispose() {
    StreamProxyServer().dispose();
    _positionController.close();
    _durationController.close();
    super.dispose();
  }
}
