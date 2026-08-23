// lib/services/audio_handler.dart
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

/// BackgroundAudioHandler - provides native background audio service & system notification controls via NewPipeExtractor
class BackgroundAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  static const _extractorChannel = MethodChannel('com.submarine/extractor');
  String? _currentVideoId;
  int _retryCount = 0;

  BackgroundAudioHandler() {
    _init();
  }

  AudioPlayer get player => _player;

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    _player.playerStateStream.listen((state) {
      final playing = state.playing;
      final proc = state.processingState;

      final audioProc = switch (proc) {
        ProcessingState.idle      => AudioProcessingState.idle,
        ProcessingState.loading   => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready     => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      };

      playbackState.add(playbackState.value.copyWith(
        processingState: audioProc,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.play,
          MediaAction.pause,
          MediaAction.playPause,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
          MediaAction.stop,
        },
        androidCompactActionIndices: const [0, 1, 2],
      ));
    });

    _player.durationStream.listen((dur) {
      if (dur != null && dur > Duration.zero) {
        final cur = mediaItem.value;
        if (cur != null && cur.duration != dur) {
          mediaItem.add(cur.copyWith(duration: dur));
        }
      }
    });

    // Handle playback errors and auto-recover with fresh stream URL
    _player.playbackEventStream.listen(
      (event) {},
      onError: (Object e, StackTrace st) {
        debugPrint('[AudioHandler] Playback error event: $e');
        _handleStreamRecovery();
      },
    );
  }

  Future<void> _handleStreamRecovery() async {
    final vId = _currentVideoId;
    final item = mediaItem.value;
    if (vId != null && item != null && _retryCount < 2) {
      _retryCount++;
      final currentPos = _player.position;
      debugPrint('[AudioHandler] Auto-recovering stream for $vId at $currentPos (attempt $_retryCount)...');
      try {
        await Future.delayed(const Duration(milliseconds: 500));
        await playOnline(vId, item, startPosition: currentPos);
      } catch (e) {
        debugPrint('[AudioHandler] Stream recovery failed: $e');
      }
    }
  }

  /// Update system notification with current song details and playing state
  Future<void> updateNotification(MediaItem item, {required bool isPlaying}) async {
    mediaItem.add(item);
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.ready,
      playing: isPlaying,
      controls: [
        MediaControl.skipToPrevious,
        isPlaying ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.play,
        MediaAction.pause,
        MediaAction.playPause,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.stop,
      },
      androidCompactActionIndices: const [0, 1, 2],
    ));
  }

  /// Play online song natively with ExoPlayer direct streaming without corrupted partial caching
  Future<void> playOnline(String videoId, MediaItem item, {Duration? startPosition}) async {
    _currentVideoId = videoId;
    _retryCount = 0;
    mediaItem.add(item);
    try {
      await _player.stop();
      debugPrint('[AudioHandler] Extracting stream for $videoId via NewPipeExtractor...');
      
      final result = await _extractorChannel.invokeMethod<Map>('getAudioStreamUrl', {
        'videoId': videoId,
      });

      if (result == null || result['url'] == null) {
        throw Exception('Failed to extract stream URL from NewPipeExtractor');
      }

      final streamUrl = result['url'] as String;
      final bitrate = result['bitrate'];
      final format = result['format'];
      debugPrint('[AudioHandler] Playing native stream: $format ($bitrate bps)');

      // Direct ExoPlayer native streaming with full standard headers
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(streamUrl),
          headers: const {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Referer': 'https://www.youtube.com/',
            'Origin': 'https://www.youtube.com',
          },
        ),
        initialPosition: startPosition,
        preload: true,
      );
      await _player.play();
    } catch (e) {
      debugPrint('[AudioHandler] playOnline error: $e');
      rethrow;
    }
  }

  /// Play offline local file
  Future<void> playFile(String path, MediaItem item) async {
    _currentVideoId = null;
    mediaItem.add(item);
    try {
      await _player.stop();
      debugPrint('[AudioHandler] Setting file source: $path');
      await _player.setAudioSource(
        AudioSource.file(path),
        preload: true,
      );
      await _player.play();
      debugPrint('[AudioHandler] Playing offline file successfully: ${item.title}');
    } catch (e) {
      debugPrint('[AudioHandler] playFile error: $e');
      rethrow;
    }
  }

  @override
  Future<void> updateMediaItem(MediaItem item) async => mediaItem.add(item);

  @override
  Future<void> play() async {
    customEvent.add('play');
    await _player.play();
  }

  @override
  Future<void> pause() async {
    customEvent.add('pause');
    await _player.pause();
  }

  @override
  Future<void> seek(Duration position) async => _player.seek(position);

  @override
  Future<void> stop() async {
    await _player.stop();
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
    customEvent.add('stop');
    await super.stop();
  }

  @override
  Future<void> skipToNext() async => customEvent.add('skipToNext');

  @override
  Future<void> skipToPrevious() async => customEvent.add('skipToPrevious');

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == 'dispose') {
      await _player.dispose();
      await super.stop();
    }
  }
}
