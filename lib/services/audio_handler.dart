// lib/services/audio_handler.dart
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// BackgroundAudioHandler – bridge between audio_service and just_audio.
class BackgroundAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer(
    audioLoadConfiguration: const AudioLoadConfiguration(
      androidLoadControl: AndroidLoadControl(
        minBufferDuration: Duration(seconds: 15),
        maxBufferDuration: Duration(seconds: 60),
        prioritizeTimeOverSizeThresholds: true,
      ),
    ),
  );

  bool _isChangingTrack = false;

  BackgroundAudioHandler() {
    _initAudioSession();
    _player.playbackEventStream.listen(_broadcastState);
    _player.playingStream.listen((playing) {
      if (playbackState.value.playing != playing) {
        _broadcastState(_player.playbackEvent);
      }
    });
    _player.durationStream.listen((duration) {
      if (duration != null && duration > Duration.zero) {
        final current = mediaItem.value;
        if (current != null && current.duration != duration) {
          mediaItem.add(current.copyWith(duration: duration));
        }
      }
    });
    _player.processingStateStream.listen((state) {
      if (_isChangingTrack && state != ProcessingState.ready) {
        _broadcastState(_player.playbackEvent);
        return;
      }
      if (state == ProcessingState.ready) {
        _isChangingTrack = false;
        _broadcastState(_player.playbackEvent);
        return;
      }
      if (state == ProcessingState.completed) {
        final position = _player.position;
        final duration = _player.duration;
        if (duration != null && duration.inSeconds > 0) {
          if ((duration - position).inSeconds > 10) {
            debugPrint('[AudioHandler] Premature EOF, recovering...');
            customEvent.add('recoverPrematureEOF');
            return;
          }
        }
        skipToNext();
      }
    });
  }

  Future<void> _initAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  AudioPlayer get player => _player;

  /// Load audio from remote URL or local file
  Future<void> loadUrl(String url, MediaItem item, {Map<String, String>? headers}) async {
    _isChangingTrack = true;
    mediaItem.add(item);
    try {
      AudioSource source;
      if (url.startsWith('http')) {
        final effectiveHeaders = Map<String, String>.from(headers ?? {});
        if (!effectiveHeaders.containsKey('User-Agent')) {
          effectiveHeaders['User-Agent'] =
              'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip';
        }
        debugPrint('[AudioHandler] Loading remote audio source with native streaming: $url');
        source = AudioSource.uri(
          Uri.parse(url),
          headers: effectiveHeaders,
        );
      } else {
        debugPrint('[AudioHandler] Loading local file source: $url');
        source = AudioSource.uri(Uri.file(url));
      }
      await _player.setAudioSource(source, preload: false);
    } catch (e) {
      _isChangingTrack = false;
      playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.error,
      ));
      rethrow;
    }
  }

  @override Future<void> play() async => _player.play();
  @override Future<void> pause() async => _player.pause();
  @override Future<void> seek(Duration position) async => _player.seek(position);

  @override
  Future<void> stop() async {
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
    await _player.stop();
    await super.stop();
  }

  @override Future<void> skipToNext() async => customEvent.add('skipToNext');
  @override Future<void> skipToPrevious() async => customEvent.add('skipToPrevious');

  void _broadcastState(PlaybackEvent event) {
    try {
      final playing = _player.playing;
      playbackState.add(playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward,
          MediaAction.play, MediaAction.pause, MediaAction.playPause,
          MediaAction.skipToNext, MediaAction.skipToPrevious, MediaAction.stop,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[_player.processingState]!,
        bufferedPosition: event.bufferedPosition,
        updatePosition: _player.position,
        playing: playing,
        speed: _player.speed,
        queueIndex: event.currentIndex,
      ));
    } catch (e, stack) {
      debugPrint('[AudioHandler] Broadcast ERROR: $e\n$stack');
    }
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == 'dispose') {
      await _player.dispose();
      await super.stop();
    }
  }
}
