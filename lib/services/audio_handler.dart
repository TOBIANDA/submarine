// lib/services/audio_handler.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

/// InnertubeAudioSource - in-memory streaming audio source for ExoPlayer
class InnertubeAudioSource extends StreamAudioSource {
  final String streamUrl;
  final int? contentLength;
  final String userAgent;

  InnertubeAudioSource({
    required this.streamUrl,
    required this.contentLength,
    required this.userAgent,
  });

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= (contentLength != null && contentLength! > 0 ? contentLength : null);

    final client = http.Client();
    final req = http.Request('GET', Uri.parse(streamUrl));
    req.headers['User-Agent'] = userAgent;
    if (start > 0 || end != null) {
      req.headers['Range'] = 'bytes=$start-${end != null ? end - 1 : ""}';
    }

    final streamed = await client.send(req);

    return StreamAudioResponse(
      rangeRequestsSupported: true,
      sourceLength: (contentLength != null && contentLength! > 0) ? contentLength : streamed.contentLength,
      contentLength: streamed.contentLength,
      offset: start,
      stream: streamed.stream,
      contentType: 'audio/mp4',
    );
  }
}

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

  /// Resolve Innertube Android direct stream URL & content length
  Future<(String, int)?> _resolveInnertubeStream(String videoId) async {
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

          final chosen = audioStreams.first;
          final url = chosen['url'] as String;
          final clen = int.tryParse(chosen['contentLength']?.toString() ?? '0') ?? 0;
          return (url, clen);
        }
      }
    } catch (e) {
      debugPrint('[AudioHandler] Resolve Innertube URL error: $e');
    } finally {
      httpClient.close();
    }
    return null;
  }

  /// Play online song natively with ExoPlayer StreamAudioSource
  Future<void> playOnline(String videoId, MediaItem item) async {
    mediaItem.add(item);
    try {
      await _player.stop();
      final streamInfo = await _resolveInnertubeStream(videoId);
      if (streamInfo == null) {
        throw Exception('Stream URL resolution failed');
      }

      final (url, clen) = streamInfo;
      debugPrint('[AudioHandler] Streaming native ExoPlayer via StreamAudioSource: ${item.title}');
      await _player.setAudioSource(
        InnertubeAudioSource(
          streamUrl: url,
          contentLength: clen,
          userAgent: _innertubeUa,
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
