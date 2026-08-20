// lib/services/audio_handler.dart
import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// BackgroundAudioHandler - provides native background audio service & system notification controls.
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

  static const String _ua = 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip';
  final YoutubeExplode _yt = YoutubeExplode();
  HttpServer? _proxyServer;
  int _proxyPort = 0;

  BackgroundAudioHandler() {
    _init();
  }

  AudioPlayer get player => _player;

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // Start fast local loopback audio proxy
    await _startProxyServer();

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

  Future<void> _startProxyServer() async {
    if (_proxyServer != null) return;
    try {
      _proxyServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _proxyPort = _proxyServer!.port;
      debugPrint('[AudioHandler] Fast local audio proxy listening on port $_proxyPort');

      _proxyServer!.listen((HttpRequest request) async {
        final targetUrl = request.uri.queryParameters['url'];
        if (targetUrl == null || targetUrl.isEmpty) {
          request.response.statusCode = HttpStatus.badRequest;
          await request.response.close();
          return;
        }

        http.Client? upstreamClient;
        try {
          upstreamClient = http.Client();
          final req = http.Request('GET', Uri.parse(targetUrl));
          req.headers['User-Agent'] = _ua;
          
          final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
          if (rangeHeader != null) {
            req.headers['Range'] = rangeHeader;
          }

          final upstream = await upstreamClient.send(req);

          request.response.statusCode = upstream.statusCode;
          request.response.headers.contentType = ContentType('audio', 'mp4');
          if (upstream.contentLength != null) {
            request.response.contentLength = upstream.contentLength!;
          }

          final acceptRanges = upstream.headers['accept-ranges'];
          if (acceptRanges != null) {
            request.response.headers.set('accept-ranges', acceptRanges);
          }
          final contentRange = upstream.headers['content-range'];
          if (contentRange != null) {
            request.response.headers.set('content-range', contentRange);
          }

          await request.response.addStream(upstream.stream);
          await request.response.close();
        } catch (e) {
          try {
            request.response.statusCode = HttpStatus.internalServerError;
            await request.response.close();
          } catch (_) {}
        } finally {
          upstreamClient?.close();
        }
      });
    } catch (e) {
      debugPrint('[AudioHandler] Proxy server bind error: $e');
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

  /// Play online song natively with ExoPlayer via pre-resolved fast loopback proxy
  Future<void> playOnline(String videoId, MediaItem item) async {
    mediaItem.add(item);
    try {
      await _player.stop();
      if (_proxyPort == 0) {
        await _startProxyServer();
      }

      debugPrint('[AudioHandler] Resolving YouTube stream for $videoId...');
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final audioStream = manifest.audioOnly.firstWhere(
        (s) => s.tag == 140,
        orElse: () => manifest.audioOnly.withHighestBitrate(),
      );
      final rawStreamUrl = audioStream.url.toString();

      final proxyUri = Uri.parse('http://127.0.0.1:$_proxyPort/stream?url=${Uri.encodeComponent(rawStreamUrl)}');
      debugPrint('[AudioHandler] Starting ExoPlayer on pre-resolved proxy stream: $proxyUri');
      
      await _player.setAudioSource(
        AudioSource.uri(proxyUri),
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
      _proxyServer?.close(force: true);
      _yt.close();
      await _player.dispose();
      await super.stop();
    }
  }
}
