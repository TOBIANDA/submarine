// lib/services/audio_handler.dart
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// BackgroundAudioHandler - bridges audio_service and Android media notification.
class BackgroundAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  BackgroundAudioHandler() {
    _initAudioSession();
  }

  Future<void> _initAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  AudioPlayer get player => _player;

  /// Updates media notification and media session without competing for Audio Focus
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
        MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward,
        MediaAction.play, MediaAction.pause, MediaAction.playPause,
        MediaAction.skipToNext, MediaAction.skipToPrevious, MediaAction.stop,
      },
      androidCompactActionIndices: const [0, 1, 2],
    ));
  }

  /// Load audio from offline local file
  Future<void> loadUrl(String filePath, MediaItem item) async {
    mediaItem.add(item);
    final source = AudioSource.uri(Uri.file(filePath));
    await _player.setAudioSource(source, preload: true);
  }

  @override
  Future<void> play() async {
    customEvent.add('play');
  }

  @override
  Future<void> pause() async {
    customEvent.add('pause');
  }

  @override
  Future<void> seek(Duration position) async {
    customEvent.add({'action': 'seek', 'position': position.inMilliseconds});
  }

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

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == 'dispose') {
      await _player.dispose();
      await super.stop();
    }
  }
}
