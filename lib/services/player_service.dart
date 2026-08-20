// lib/services/player_service.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:path_provider/path_provider.dart';

import '../models/video_item.dart';
import '../models/play_history.dart';
import '../services/db_service.dart';
import '../services/audio_handler.dart';

enum RepeatMode { none, all, one }

class PlayerService extends ChangeNotifier {
  static PlayerService? _instance;
  PlayerService._();
  factory PlayerService() => _instance ??= PlayerService._();

  late BackgroundAudioHandler _audioHandler;
  AudioPlayer get audioPlayer => _audioHandler.player;

  List<VideoItem> _playlist = [];
  int _currentIndex = -1;
  bool _isShuffle = false;
  RepeatMode _repeatMode = RepeatMode.none;
  bool _audioFocusMode = true;
  bool _isLoadingAudio = false;

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
  bool get hasNext => _playlist.isNotEmpty && _currentIndex < _playlist.length - 1;
  bool get hasPrevious => _playlist.isNotEmpty && _currentIndex > 0;

  Stream<Duration> get positionStream => audioPlayer.positionStream;
  Stream<Duration?> get durationStream => audioPlayer.durationStream;
  Duration get position => audioPlayer.position;
  Duration? get duration => audioPlayer.duration;

  Future<void> init(BackgroundAudioHandler handler) async {
    _audioHandler = handler;

    audioPlayer.playerStateStream.listen((state) { if (state.playing) { _isLoadingAudio = false; }
      notifyListeners();
    });

    audioPlayer.playbackEventStream.listen((event) {}, onError: (e) {
      debugPrint('[Player] Player error event: $e');
      _isLoadingAudio = false;
      notifyListeners();
    });

    audioPlayer.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _onTrackEnded();
      }
      notifyListeners();
    });

    _audioHandler.customEvent.listen((event) {
      if (event == 'skipToNext') playNext();
      if (event == 'skipToPrevious') playPrevious();
      if (event == 'play') play();
      if (event == 'pause') pause();
    });
  }

  Future<void> loadQueue(List<VideoItem> items, {int startIndex = 0, int? initialIndex, String? playlistId}) async {
    if (items.isEmpty) return;
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
      _currentIndex = index;
      notifyListeners();
      await _playCurrent();
    }
  }

  Future<void> _playCurrent() async {
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
        durationSeconds: video.durationSeconds,
        lastPositionSeconds: 0,
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
      final dir = await getApplicationDocumentsDirectory();
      final mp3 = File('${dir.path}/downloads/$videoId.mp3');
      if (await mp3.exists()) return mp3.path;
      final m4a = File('${dir.path}/downloads/$videoId.m4a');
      if (await m4a.exists()) return m4a.path;
    } catch (_) {}
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
    if (_currentIndex > 0) {
      _currentIndex--;
    } else {
      _currentIndex = _playlist.length - 1;
    }
    notifyListeners();
    await _playCurrent();
  }

  Future<void> stop() async {
    await _audioHandler.stop();
    _playlist.clear();
    _currentIndex = -1;
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
    } else if (hasNext) {
      playNext();
    }
  }
}
