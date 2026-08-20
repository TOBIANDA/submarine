// lib/services/audio_handler.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

class _SilenceAudioSource extends StreamAudioSource {
  static final Uint8List _wav = Uint8List.fromList([
    0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00, 0x00, 0x57, 0x41, 0x56, 0x45,
    0x66, 0x6d, 0x74, 0x20, 0x10, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00,
    0x44, 0xac, 0x00, 0x00, 0x88, 0x58, 0x01, 0x00, 0x02, 0x00, 0x10, 0x00,
    0x64, 0x61, 0x74, 0x61, 0x00, 0x00, 0x00, 0x00
  ]);

  _SilenceAudioSource() : super(tag: 'Silence');

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    return StreamAudioResponse(
      sourceLength: _wav.length,
      contentLength: _wav.length,
      offset: 0,
      contentType: 'audio/wav',
      stream: Stream.value(_wav),
    );
  }
}

/// BackgroundAudioHandler – bridges audio_service and Android media notification.
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

  /// Starts native Android foreground notification & audio focus keep-alive
  Future<void> startBackgroundKeepAlive(MediaItem item) async {
    mediaItem.add(item);
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.ready,
      playing: true,
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.pause,
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

    try {
      await _player.setLoopMode(LoopMode.one);
      await _player.setAudioSource(_SilenceAudioSource(), preload: true);
      await _player.play();
      debugPrint('[AudioHandler] ✅ Native foreground keep-alive active');
    } catch (e) {
      debugPrint('[AudioHandler] Keep-alive error: $e');
    }
  }

  Future<void> pauseBackgroundKeepAlive() async {
    playbackState.add(playbackState.value.copyWith(
      playing: false,
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
    ));
    await _player.pause();
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
