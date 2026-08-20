// lib/services/audio_handler.dart
import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// BackgroundAudioHandler - Native Android ExoPlayer driven by Foreground Service
class BackgroundAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  final YoutubeExplode _yt = YoutubeExplode();
  
  StreamSubscription? _downloadSub;
  IOSink? _activeSink;
  File? _activeFile;

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

    _player.positionStream.listen((pos) {
      playbackState.add(playbackState.value.copyWith(updatePosition: pos));
    });
  }

  /// Play YouTube video online via background streaming cache
  Future<void> playOnlineVideo(String videoId, MediaItem item) async {
    mediaItem.add(item);
    _cancelActiveStream();

    try {
      await _player.stop();
      debugPrint('[AudioHandler] Resolving stream manifest for: ${item.title} ($videoId)');
      
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final audioStreams = manifest.audioOnly;
      final bestAudio = audioStreams.withHighestBitrate();
      debugPrint('[AudioHandler] Best audio stream: ${bestAudio.container.name}, ${bestAudio.bitrate.kiloBitsPerSecond} kbps');

      final tempDir = await getTemporaryDirectory();
      final cacheFile = File('${tempDir.path}/cache_${videoId}.${bestAudio.container.name}');
      if (cacheFile.existsSync()) {
        try { cacheFile.deleteSync(); } catch (_) {}
      }

      final sink = cacheFile.openWrite();
      _activeSink = sink;
      _activeFile = cacheFile;

      final byteStream = _yt.videos.streamsClient.get(bestAudio);
      final completer = Completer<void>();
      int receivedBytes = 0;
      bool playbackStarted = false;

      _downloadSub = byteStream.listen(
        (chunk) async {
          sink.add(chunk);
          receivedBytes += chunk.length;

          // Start playing as soon as first 120KB are buffered (~0.3s)
          if (!playbackStarted && (receivedBytes >= 120000 || receivedBytes >= bestAudio.size.totalBytes)) {
            playbackStarted = true;
            try {
              await _player.setAudioSource(
                AudioSource.uri(Uri.file(cacheFile.path)),
                preload: true,
              );
              await _player.play();
              debugPrint('[AudioHandler] Native playback started smoothly from cache file: ${cacheFile.path}');
              if (!completer.isCompleted) completer.complete();
            } catch (e) {
              debugPrint('[AudioHandler] setAudioSource initial error: $e');
            }
          }
        },
        onError: (e) {
          debugPrint('[AudioHandler] Byte stream error: $e');
          if (!completer.isCompleted) completer.completeError(e);
        },
        onDone: () async {
          debugPrint('[AudioHandler] Finished caching all $receivedBytes bytes for $videoId');
          try {
            await sink.flush();
            await sink.close();
          } catch (_) {}
          if (!playbackStarted) {
            try {
              await _player.setAudioSource(
                AudioSource.uri(Uri.file(cacheFile.path)),
                preload: true,
              );
              await _player.play();
              if (!completer.isCompleted) completer.complete();
            } catch (e) {
              if (!completer.isCompleted) completer.completeError(e);
            }
          }
        },
        cancelOnError: true,
      );

      await completer.future.timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('[AudioHandler] playOnlineVideo error: $e');
      rethrow;
    }
  }

  /// Play offline local file
  Future<void> playFile(String path, MediaItem item) async {
    mediaItem.add(item);
    _cancelActiveStream();
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

  void _cancelActiveStream() {
    _downloadSub?.cancel();
    _downloadSub = null;
    try {
      _activeSink?.close();
    } catch (_) {}
    _activeSink = null;
  }

  @override
  Future<void> updateMediaItem(MediaItem item) async {
    mediaItem.add(item);
  }

  @override
  Future<void> play() async => _player.play();

  @override
  Future<void> pause() async => _player.pause();

  @override
  Future<void> seek(Duration position) async => _player.seek(position);

  @override
  Future<void> stop() async {
    _cancelActiveStream();
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
      _cancelActiveStream();
      _yt.close();
      await _player.dispose();
      await super.stop();
    }
  }
}
