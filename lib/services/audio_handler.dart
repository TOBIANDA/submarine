// lib/services/audio_handler.dart
import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

/// BackgroundAudioHandler - provides native background audio service & system notification controls via NewPipeExtractor
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

  static const _extractorChannel = MethodChannel('com.submarine/extractor');

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

  /// Play online song natively with ExoPlayer using NewPipeExtractor signed stream URL
  Future<void> playOnline(String videoId, MediaItem item) async {
    mediaItem.add(item);
    try {
      await _player.stop();
      debugPrint('[AudioHandler] Calling native NewPipeExtractor for $videoId...');
      
      final result = await _extractorChannel.invokeMethod<Map>('getAudioStreamUrl', {
        'videoId': videoId,
      });

      if (result == null || result['url'] == null) {
        throw Exception('Failed to extract stream URL from NewPipeExtractor');
      }

      final streamUrl = result['url'] as String;
      final bitrate = result['bitrate'];
      final format = result['format'];
      debugPrint('[AudioHandler] NewPipe stream acquired: $format ($bitrate bps)');

      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(streamUrl),
          headers: const {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          },
        ),
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
    mediaItem.add(item);
    try {
      await _player.stop();
      await _player.setAudioSource(
        AudioSource.uri(Uri.file(path)),
        preload: true,
      );
      await _player.play();
      debugPrint('[AudioHandler] Playing offline file: ${item.title}');
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
