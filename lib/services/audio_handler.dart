// lib/services/audio_handler.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

/// BackgroundAudioHandler - provides native ExoPlayer foreground audio playback & system notification controls.
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

  static const String _innertubeUa = 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip';
  http.Client? _activeStreamClient;
  IOSink? _activeFileSink;
  int _streamSessionId = 0;

  BackgroundAudioHandler() {
    _init();
  }

  AudioPlayer get player => _player;

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // Listen to ExoPlayer playback events
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

  /// Resolve Innertube Android direct stream URL
  Future<String?> _resolveInnertubeStreamUrl(String videoId) async {
    final httpClient = http.Client();
    try {
      final resp = await httpClient.post(
        Uri.parse('https://www.youtube.com/youtubei/v1/player'),
        headers: {
          'User-Agent': _innertubeUa,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'context': {
            'client': {
              'clientName': 'ANDROID',
              'clientVersion': '20.10.38',
              'androidSdkVersion': 30,
              'userAgent': _innertubeUa,
              'hl': 'en',
              'gl': 'US',
            }
          },
          'videoId': videoId,
        }),
      ).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final formats = (data['streamingData']?['adaptiveFormats'] as List?) ?? [];
        final audioStreams = formats.where((f) {
          final mime = f['mimeType'] as String? ?? '';
          return mime.startsWith('audio/') && f['url'] != null;
        }).toList();

        if (audioStreams.isNotEmpty) {
          audioStreams.sort((a, b) {
            final a140 = (a['itag'] == 140) ? 1 : 0;
            final b140 = (b['itag'] == 140) ? 1 : 0;
            if (a140 != b140) return b140.compareTo(a140);
            return ((b['bitrate'] as int?) ?? 0).compareTo((a['bitrate'] as int?) ?? 0);
          });

          return audioStreams.first['url'] as String;
        }
      }
    } catch (e) {
      debugPrint('[AudioHandler] Resolve Innertube URL error: $e');
    } finally {
      httpClient.close();
    }
    return null;
  }

  /// Play online song natively with ExoPlayer background stream cache
  Future<void> playOnline(String videoId, MediaItem item) async {
    mediaItem.add(item);
    _streamSessionId++;
    final currentSession = _streamSessionId;

    try {
      _activeStreamClient?.close();
      await _activeFileSink?.close();
      await _player.stop();

      final streamUrl = await _resolveInnertubeStreamUrl(videoId);
      if (streamUrl == null) throw Exception('Gagal mendapatkan stream URL');

      final tempDir = await getTemporaryDirectory();
      final cacheFile = File('${tempDir.path}/stream_$videoId.m4a');

      // Jika file cache utuh sudah ada (>500KB), langsung putar instan!
      if (cacheFile.existsSync() && cacheFile.lengthSync() > 500000) {
        debugPrint('[AudioHandler] Playing existing cached stream: ${item.title}');
        await _player.setAudioSource(AudioSource.uri(Uri.file(cacheFile.path)));
        await _player.play();
        return;
      }

      if (cacheFile.existsSync()) cacheFile.deleteSync();

      final client = http.Client();
      _activeStreamClient = client;
      final req = http.Request('GET', Uri.parse(streamUrl));
      req.headers['User-Agent'] = _innertubeUa;

      final streamed = await client.send(req);
      if (streamed.statusCode != 200 && streamed.statusCode != 206) {
        client.close();
        throw Exception('Stream request error: HTTP ${streamed.statusCode}');
      }

      final sink = cacheFile.openWrite();
      _activeFileSink = sink;

      final completer = Completer<void>();
      int bufferedBytes = 0;
      bool playbackStarted = false;

      // Stream chunks into local cache file and trigger ExoPlayer as soon as 100KB buffered
      streamed.stream.listen(
        (chunk) async {
          if (_streamSessionId != currentSession) return;
          sink.add(chunk);
          bufferedBytes += chunk.length;

          if (!playbackStarted && bufferedBytes >= 100000) {
            playbackStarted = true;
            await sink.flush();
            try {
              if (_streamSessionId != currentSession) return;
              debugPrint('[AudioHandler] Pre-buffered $bufferedBytes bytes -> Starting ExoPlayer!');
              await _player.setAudioSource(
                AudioSource.uri(Uri.file(cacheFile.path)),
                preload: true,
              );
              await _player.play();
              if (!completer.isCompleted) completer.complete();
            } catch (e) {
              debugPrint('[AudioHandler] Pre-buffered player error: $e');
              if (!completer.isCompleted) completer.completeError(e);
            }
          }
        },
        onDone: () async {
          await sink.flush();
          await sink.close();
          client.close();
          if (!playbackStarted && _streamSessionId == currentSession) {
            try {
              await _player.setAudioSource(AudioSource.uri(Uri.file(cacheFile.path)));
              await _player.play();
              if (!completer.isCompleted) completer.complete();
            } catch (e) {
              if (!completer.isCompleted) completer.completeError(e);
            }
          }
        },
        onError: (err) {
          if (!completer.isCompleted) completer.completeError(err);
        },
        cancelOnError: true,
      );

      // Wait up to 10 seconds for initial 100KB buffer to start playback
      await completer.future.timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[AudioHandler] playOnline error: $e');
      rethrow;
    }
  }

  /// Play offline local file
  Future<void> playFile(String path, MediaItem item) async {
    mediaItem.add(item);
    try {
      _activeStreamClient?.close();
      await _activeFileSink?.close();
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
    _streamSessionId++;
    _activeStreamClient?.close();
    await _activeFileSink?.close();
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
      _streamSessionId++;
      _activeStreamClient?.close();
      await _activeFileSink?.close();
      await _player.dispose();
      await super.stop();
    }
  }
}
