import 'package:http/http.dart' as http;
// lib/services/audio_handler.dart
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// BackgroundAudioHandler — jembatan antara audio_service dan just_audio.
/// Menangani foreground service, notifikasi lock screen, dan kontrol media.
class BackgroundAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer(
    // Konfigurasi buffer Android agar buffering awal lebih cepat
    // dan mengurangi kemungkinan stuck saat stream dimulai
    audioLoadConfiguration: const AudioLoadConfiguration(
      androidLoadControl: AndroidLoadControl(
        minBufferDuration: Duration(seconds: 10),
        maxBufferDuration: Duration(seconds: 45),
        prioritizeTimeOverSizeThresholds: true,
      ),
    ),
  );

  // Guard agar event 'completed' tidak terpicu saat track sedang berpindah.
  // Ini mencegah bug lagu skip-skip sendiri akibat race condition.
  bool _isChangingTrack = false;

  BackgroundAudioHandler() {
    _initAudioSession();
    // Forward player state changes ke audio_service
    _player.playbackEventStream.listen(_broadcastState);
    
    // just_audio's playbackEventStream tidak memancarkan event saat status 'playing' berubah
    // (misalnya saat kita memanggil _player.play()), jadi kita harus listen ke playingStream juga.
    _player.playingStream.listen((playing) {
      if (playbackState.value.playing != playing) {
        _broadcastState(_player.playbackEvent);
      }
    });

    // TAMBAHAN: sinkronkan duration asli dari just_audio ke MediaItem
    _player.durationStream.listen((duration) {
      if (duration != null && duration > Duration.zero) {
        final current = mediaItem.value;
        if (current != null && current.duration != duration) {
          mediaItem.add(current.copyWith(duration: duration));
        }
      }
    });

    _player.processingStateStream.listen((state) {
      // Abaikan event saat track sedang ganti untuk hindari false skip
      if (_isChangingTrack && state != ProcessingState.ready) {
        _broadcastState(_player.playbackEvent);
        return;
      }
      // Clear flag saat player sudah siap
      if (state == ProcessingState.ready) {
        _isChangingTrack = false;
        _broadcastState(_player.playbackEvent);
        return;
      }

      if (state == ProcessingState.completed) {
        final position = _player.position;
        final duration = _player.duration;
        
        // Cek jika EOF prematur (koneksi terputus tiba-tiba atau file corrupt di tengah)
        // Threshold dinaikkan ke 10 detik untuk menghindari false positive
        if (duration != null && duration.inSeconds > 0) {
          if ((duration - position).inSeconds > 10) {
            debugPrint('[AudioHandler] Premature EOF terdeteksi, mencoba memulihkan stream...');
            customEvent.add('recoverPrematureEOF');
            return;
          }
        } else {
           debugPrint('[AudioHandler] Durasi null/0 saat completed, mencoba auto-skip.');
        }

        // Trigger auto-advance via skipToNext
        skipToNext();
      }
    });
  }

  Future<void> _initAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  // ─── Public accessor ─────────────────────────────────
  AudioPlayer get player => _player;

  // ─── Load audio from URL ──────────────────────────────
    Future<void> loadAudioSource(AudioSource source, MediaItem item) async {
    _isChangingTrack = true;
    mediaItem.add(item);
    try {
      await _player.setAudioSource(source, preload: true);
    } catch (e) {
      _isChangingTrack = false;
      playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.error,
      ));
      rethrow;
    }
  }

  Future<void> loadUrl(String url, MediaItem item, {String? userAgent, int? size, String? mime}) async {
    if (url.startsWith('http') && size != null && size > 0) {
      final source = YouTubeStreamAudioSource(
        streamUrl: Uri.parse(url),
        totalBytes: size,
        mimeType: mime ?? 'audio/webm',
        tag: item,
      );
      await loadAudioSource(source, item);
    } else {
      _isChangingTrack = true;
      mediaItem.add(item);
      try {
        await _player.setAudioSource(
          AudioSource.uri(
            url.startsWith('http') ? Uri.parse(url) : Uri.file(url),
          ),
          preload: true,
        );
      } catch (e) {
        _isChangingTrack = false;
        playbackState.add(playbackState.value.copyWith(
          processingState: AudioProcessingState.error,
        ));
        rethrow;
      }
    }
  }

  // ─── BaseAudioHandler overrides ───────────────────────
  @override
  Future<void> play() async {
    await _player.play();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  @override
  Future<void> stop() async {
    // Broadcast idle state dulu agar Android tahu media session sudah selesai.
    // Ini yang membuat notifikasi bisa hilang saat app di-kill dari recent apps.
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async {
    customEvent.add('skipToNext');
  }

  @override
  Future<void> skipToPrevious() async {
    customEvent.add('skipToPrevious');
  }

  // ─── Internal ─────────────────────────────────────────
  void _broadcastState(PlaybackEvent event) {
    try {
      final playing = _player.playing;
      debugPrint('[AudioHandler] Broadcasting state: playing=$playing, processingState=${_player.processingState}');
      playbackState.add(playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
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
      debugPrint('[AudioHandler] Broadcast success');
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


class YouTubeStreamAudioSource extends StreamAudioSource {
  final Uri streamUrl;
  final int totalBytes;
  final String mimeType;

  YouTubeStreamAudioSource({
    required this.streamUrl,
    required this.totalBytes,
    required this.mimeType,
    dynamic tag,
  }) : super(tag: tag);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= totalBytes;
    final rangeEnd = end > 0 ? end - 1 : 0;

    final requestHeaders = <String, String>{
      'Range': 'bytes=$start-$rangeEnd',
      'User-Agent': 'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 Chrome/122.0.0.0 Mobile Safari/537.36',
    };

    final req = http.Request('GET', streamUrl)..headers.addAll(requestHeaders);
    final response = await http.Client().send(req);

    return StreamAudioResponse(
      sourceLength: totalBytes,
      contentLength: end - start,
      offset: start,
      stream: response.stream,
      contentType: mimeType,
    );
  }
}
