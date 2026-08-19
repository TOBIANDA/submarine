import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/video_item.dart';
import '../models/play_history.dart';
import 'audio_handler.dart';
import 'db_service.dart';
import 'youtube_service.dart';
import 'ai_service.dart';

export 'package:just_audio/just_audio.dart' show AudioPlayer;

enum RepeatMode { none, all, one }

class PlayerService extends ChangeNotifier {
  static PlayerService? _instance;
  PlayerService._();
  factory PlayerService() => _instance ??= PlayerService._();

  BackgroundAudioHandler? _audioHandler;
  final YoutubeExplode _yt = YoutubeExplode();

  // â”€â”€â”€ State â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  VideoItem? _currentVideo;
  List<VideoItem> _queue = [];
  int _currentIndex = -1;
  bool _isPlaying = false;
  bool _isShuffled = false;
  RepeatMode _repeatMode = RepeatMode.none;
  bool _audioFocusMode = false;
  String? _currentPlaylistId;
  bool _isLoadingAudio = false;

  // Shuffle queue state
  List<int> _shuffleHistory = [];
  List<int> _unplayedShuffleIndices = [];

  // Cancellation token for overlapping loads
  int _loadId = 0;

  // Callback to invalidate history provider
  VoidCallback? onHistoryUpdated;

  // â”€â”€â”€ Init â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void init(BackgroundAudioHandler handler) {
    _audioHandler = handler;

    // Listen to playback state from audio_service
    handler.playbackState.listen((state) {
      final playing = state.playing;
      if (_isPlaying != playing) {
        _isPlaying = playing;
        notifyListeners();
      }
      // Auto-advance is now handled via customEvent from BackgroundAudioHandler
    });

    handler.customEvent.listen((event) {
      if (event == 'skipToNext') {
        playNext();
      } else if (event == 'skipToPrevious') {
        playPrevious();
      } else if (event == 'recoverPrematureEOF') {
        _recoverPlayback();
      }
    });
  }

  // â”€â”€â”€ Getters â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  VideoItem? get currentVideo => _currentVideo;
  List<VideoItem> get queue => _queue;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  bool get isShuffled => _isShuffled;
  RepeatMode get repeatMode => _repeatMode;
  bool get audioFocusMode => _audioFocusMode;
  bool get isLoadingAudio => _isLoadingAudio;
  bool get hasPrevious => _currentIndex > 0 || _repeatMode == RepeatMode.all;
  bool get hasNext =>
      _currentIndex < _queue.length - 1 || _repeatMode == RepeatMode.all;

  /// Expose the underlying AudioPlayer for position/duration streams
  AudioPlayer? get audioPlayer => _audioHandler?.player;

  // â”€â”€â”€ Playback Control â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Load a queue and optionally start at an index
  void loadQueue(List<VideoItem> items, {int startIndex = 0, String? playlistId}) {
    _queue = List.from(items);
    _currentPlaylistId = playlistId;
    _shuffleHistory = [];
    if (_isShuffled) _generateShuffleQueue();
    playAt(startIndex);
  }

  /// Play a single video immediately, replacing the queue
  void playSingle(VideoItem video) {
    _queue = [video];
    _currentPlaylistId = null;
    playAt(0);
  }

  /// Add video to queue
  void addToQueue(VideoItem video) {
    if (_queue.isEmpty || !_isPlaying) {
      _queue.add(video);
      playAt(_queue.length - 1);
    } else {
      _queue.insert((_currentIndex + 1).clamp(0, _queue.length), video);
      notifyListeners();
    }
  }

  /// Play next in queue
  void playAt(int index) {
    if (_queue.isEmpty) return;
    final clampedIndex = index.clamp(0, _queue.length - 1);
    _currentIndex = clampedIndex;
    _currentVideo = _queue[_currentIndex];
    _isPlaying = true;
    _shuffleHistory.add(clampedIndex);
    _unplayedShuffleIndices.remove(clampedIndex);
    _saveToHistory();
    notifyListeners();
    _loadAndPlayAudio(_currentVideo!);
  }

  void playNext() {
    if (_queue.isEmpty) return;

    if (_repeatMode == RepeatMode.one) {
      playAt(_currentIndex);
      return;
    }

    if (_isShuffled) {
      if (_unplayedShuffleIndices.isEmpty) {
        if (_repeatMode == RepeatMode.all || _currentPlaylistId != null) {
          _generateShuffleQueue();
        } else {
          _fetchAndPlayRelated();
          return;
        }
      }
      if (_unplayedShuffleIndices.isNotEmpty) {
        playAt(_unplayedShuffleIndices.first);
      } else {
        playAt(0);
      }
      return;
    }

    if (_currentIndex < _queue.length - 1) {
      playAt(_currentIndex + 1);
    } else {
      // End of queue
      if (_repeatMode == RepeatMode.all) {
        playAt(0);
      } else if (_currentPlaylistId != null) {
        // Logika Circular Linked List untuk Playlist
        playAt(0);
      } else {
        // Autoplay: fetch related videos hanya jika dari pencarian tunggal
        _fetchAndPlayRelated();
      }
    }
  }

  void playPrevious() {
    if (_queue.isEmpty) return;

    if (_repeatMode == RepeatMode.one) {
      playAt(_currentIndex);
      return;
    }

    if (_isShuffled && _shuffleHistory.length > 1) {
      _shuffleHistory.removeLast();
      final prevIndex = _shuffleHistory.last;
      _shuffleHistory.removeLast();
      playAt(prevIndex);
      return;
    }

    if (_currentIndex > 0) {
      playAt(_currentIndex - 1);
    } else if (_repeatMode == RepeatMode.all || _currentPlaylistId != null) {
      playAt(_queue.length - 1);
    }
  }

  int _consecutiveSuggestFailures = 0;

  /// Fitur Autoplay (Radio Mode) - Menambahkan lagu terkait saat antrean habis
    /// Fitur Autoplay (Radio Mode) - Menambahkan lagu terkait saat antrean habis dengan Anti-Duplikat AI
  Future<void> _fetchAndPlayRelated() async {
    if (_currentVideo == null || _isLoadingAudio) return;
    
    final currentVid = _currentVideo!;
    final currentTitleClean = currentVid.title
        .replaceAll(RegExp(r'\(.*?\)|\[.*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'official\s*(video|audio|lyrics|music video)?', caseSensitive: false), '')
        .trim().toLowerCase();

    _isLoadingAudio = true;
    notifyListeners();

    try {
      List<VideoItem> candidates = [];
      
      debugPrint('[Player] ðŸ¤– Meminta AI menyarankan lagu berikutnya yang serupa & berbeda...');
      final suggestion = await AiService().recommendNextSong(currentVid.title, currentVid.channelTitle);
      
      if (suggestion != null && suggestion.isNotEmpty) {
         debugPrint('[Player] ðŸŽ¯ AI Rekomendasi: $suggestion');
         final aiResults = await YoutubeService().searchVideos(suggestion, maxResults: 5);
         if (aiResults.isNotEmpty) {
            candidates.addAll(aiResults);
         }
      }

      // Fallback ke YouTube related videos jika AI gagal
      if (candidates.isEmpty) {
        debugPrint('[Player] ðŸ”„ Fallback ke YouTube related videos...');
        final relatedResults = await YoutubeService().getRelatedVideos(currentVid, maxResults: 10);
        candidates.addAll(relatedResults);
      }

      // Filter Anti-Duplikat:
      // 1. Bukan videoId yang sama
      // 2. Judul lagu tidak boleh sama persis dengan lagu saat ini (mencegah re-upload dari channel lain)
      // 3. Belum ada di antrean saat ini
      final existingIds = _queue.map((v) => v.videoId).toSet();
      existingIds.add(currentVid.videoId);

      VideoItem? bestCandidate;
      for (final candidate in candidates) {
        if (existingIds.contains(candidate.videoId)) continue;

        final candidateTitleClean = candidate.title
            .replaceAll(RegExp(r'\(.*?\)|\[.*?\]', caseSensitive: false), '')
            .replaceAll(RegExp(r'official\s*(video|audio|lyrics|music video)?', caseSensitive: false), '')
            .trim().toLowerCase();

        // Jika judul lagu sangat mirip (re-upload), lewati!
        if (candidateTitleClean == currentTitleClean || 
           (currentTitleClean.length > 5 && candidateTitleClean.contains(currentTitleClean))) {
          debugPrint('[Player] â­ï¸ Melewati lagu duplikat: ${candidate.title}');
          continue;
        }

        bestCandidate = candidate;
        break;
      }

      // Jika semua kandidat terfilter, ambil kandidat pertama yang beda videoId
      if (bestCandidate == null && candidates.isNotEmpty) {
        bestCandidate = candidates.firstWhere(
          (c) => c.videoId != currentVid.videoId,
          orElse: () => candidates.first,
        );
      }

      if (bestCandidate != null) {
        debugPrint('[Player] ðŸŽ¶ Menambahkan ke antrean autoplay: ${bestCandidate.title} - ${bestCandidate.channelTitle}');
        addToQueue(bestCandidate);
        playAt(_queue.length - 1);
        _consecutiveSuggestFailures = 0;
      } else {
        _isPlaying = false;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[Player] Gagal auto-queue lagu baru: $e');
      _consecutiveSuggestFailures++;
      _isPlaying = false;
      notifyListeners();
    } finally {
      if (_isLoadingAudio) {
        _isLoadingAudio = false;
        notifyListeners();
      }
    }
  }

  /// Memulihkan stream jika terputus tiba-tiba (Premature EOF)
  Future<void> _recoverPlayback() async {
    if (_currentVideo == null || _audioHandler == null) return;
    
    // Simpan posisi terakhir
    final position = _audioHandler!.player.position;
    debugPrint('[Player] ðŸ”„ Mencoba memulihkan stream pada posisi $position...');
    
    _isLoadingAudio = true;
    notifyListeners();
    
    try {
      _loadId++;
      final currentLoadId = _loadId;
      // Coba load stream baru dari YouTube
      await _streamFromYouTube(_currentVideo!, currentLoadId);
      // Setelah berhasil load URL dan play dipanggil di _streamFromYouTube, 
      // kita seek ke posisi terakhir
      await _audioHandler!.player.seek(position);
      debugPrint('[Player] âœ… Berhasil memulihkan stream');
    } catch (e) {
      debugPrint('[Player] âŒ Gagal memulihkan stream: $e');
      // Jika gagal pulih, terpaksa skip
      if (hasNext) {
         playNext();
      } else {
         _isPlaying = false;
         notifyListeners();
      }
    } finally {
      _isLoadingAudio = false;
      notifyListeners();
    }
  }

  void togglePlay() {
    if (_audioHandler == null) return;
    if (_isPlaying) {
      _audioHandler!.pause();
    } else {
      _audioHandler!.play();
    }
  }

  void setPlaying(bool playing) {
    if (_isPlaying != playing) {
      _isPlaying = playing;
      notifyListeners();
    }
  }

  void toggleShuffle() {
    _isShuffled = !_isShuffled;
    if (_isShuffled) _generateShuffleQueue();
    notifyListeners();
  }

  void setShuffle(bool enable) {
    if (_isShuffled != enable) {
      _isShuffled = enable;
      if (_isShuffled) _generateShuffleQueue();
      notifyListeners();
    }
  }

  void _generateShuffleQueue() {
    _unplayedShuffleIndices = List.generate(_queue.length, (i) => i);
    _unplayedShuffleIndices.remove(_currentIndex);
    _unplayedShuffleIndices.shuffle();
  }

  void cycleRepeatMode() {
    switch (_repeatMode) {
      case RepeatMode.none:
        _repeatMode = RepeatMode.all;
        break;
      case RepeatMode.all:
        _repeatMode = RepeatMode.one;
        break;
      case RepeatMode.one:
        _repeatMode = RepeatMode.none;
        break;
    }
    // Sinkronkan ke just_audio LoopMode agar repeat benar-benar aktif
    _syncLoopMode();
    notifyListeners();
  }

  /// Sinkronkan _repeatMode ke just_audio LoopMode
  void _syncLoopMode() {
    if (_audioHandler == null) return;
    final loopMode = switch (_repeatMode) {
      RepeatMode.none => LoopMode.off,
      RepeatMode.all  => LoopMode.all,
      RepeatMode.one  => LoopMode.one,
    };
    _audioHandler!.player.setLoopMode(loopMode);
    debugPrint('[Player] LoopMode set to: $loopMode');
  }

  void toggleAudioFocusMode() {
    _audioFocusMode = !_audioFocusMode;
    notifyListeners();
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= _queue.length) return;
    _queue.removeAt(index);
    if (index < _currentIndex) {
      _currentIndex--;
    } else if (index == _currentIndex) {
      if (_queue.isNotEmpty) {
        playAt(_currentIndex.clamp(0, _queue.length - 1));
      } else {
        _currentVideo = null;
        _currentIndex = -1;
        _isPlaying = false;
        _audioHandler?.stop();
      }
    }
    notifyListeners();
  }

  int _consecutiveFailures = 0;

  // â”€â”€â”€ Private â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Extract audio stream URL via youtube_explode_dart and play via just_audio.
  /// Priority: local file â†’ YouTube muxed stream â†’ YouTube audio-only fallback.
  Future<void> _loadAndPlayAudio(VideoItem video) async {
    if (_audioHandler == null) return;

    _loadId++;
    final currentLoadId = _loadId;

    _isLoadingAudio = true;
    notifyListeners();

    try {
      // 1. Cek apakah ada file offline
      final downloaded = await DbService().getDownload(video.videoId);
      bool playedOffline = false;

      if (downloaded != null && File(downloaded.localPath).existsSync()) {
        debugPrint('[Player] ðŸŽµ Mencoba memutar dari file lokal: ${downloaded.localPath}');
        final mediaItem = _buildMediaItem(video);
        if (_loadId != currentLoadId) return;
        try {
          await _audioHandler!.loadUrl(downloaded.localPath, mediaItem);
          if (_loadId != currentLoadId) return;
          
          final duration = _audioHandler!.player.duration;
          if (duration == null || duration.inSeconds == 0) {
             throw Exception('Durasi file offline 0, kemungkinan file rusak.');
          }

          _audioHandler!.play();
          playedOffline = true;
        } catch (e) {
          debugPrint('[Player] âš ï¸ File lokal gagal dimuat, file mungkin korup atau format tidak didukung. Fallback ke streaming. Error: $e');
          playedOffline = false;
        }
      } 
      
      if (!playedOffline) {
        if (_loadId != currentLoadId) return;
        // 2. Stream dari YouTube jika tidak ada file offline atau file lokal gagal
        await _streamFromYouTube(video, currentLoadId);
      }

      // Berhasil
      if (_loadId == currentLoadId) _consecutiveFailures = 0;
    } catch (e) {
      _consecutiveFailures++;
      debugPrint('[Player] AudioLoad error: $e (failures: $_consecutiveFailures)');
      _isPlaying = false;
      _currentVideo = null;
      notifyListeners();
      
      if (_consecutiveFailures >= 3) {
        debugPrint('[Player] Terlalu banyak kegagalan, hentikan skip otomatis.');
        return; // Jangan skip lagi
      }
      
      // Auto-skip ke lagu selanjutnya jika gagal total
      if (hasNext) {
        debugPrint('[Player] Auto-skipping to next track due to error...');
        playNext();
      }
    } finally {
      _isLoadingAudio = false;
      notifyListeners();
    }
  }


  /// Ambil stream URL dari YouTube dan mulai pemutaran.
  /// Menggunakan Innertube API (ViMusic/InnerTune style) yang memprioritaskan itag 140 (m4a/AAC).
  Future<void> _streamFromYouTube(VideoItem video, int currentLoadId, {int maxAttempts = 3}) async {
    debugPrint('[Player] ðŸŒ Fetching stream for: ${video.title} (${video.videoId})');
    Exception? lastError;

    final configs = [
      // 1. Android Client (itag 140 AAC)
      (
        'ANDROID',
        'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
        {
          'clientName': 'ANDROID',
          'clientVersion': '20.10.38',
          'androidSdkVersion': 30,
          'userAgent': 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
          'hl': 'en',
          'gl': 'US',
        }
      ),
      // 2. iOS Client (itag 140 AAC)
      (
        'IOS',
        'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
        {
          'clientName': 'IOS',
          'clientVersion': '20.10.4',
          'deviceModel': 'iPhone16,2',
          'userAgent': 'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
          'hl': 'en',
          'gl': 'US',
        }
      ),
    ];

    final httpClient = http.Client();

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      if (_loadId != currentLoadId) {
        httpClient.close();
        return;
      }

      for (final (clientName, userAgent, clientContext) in configs) {
        if (_loadId != currentLoadId) {
          httpClient.close();
          return;
        }

        try {
          debugPrint('[Player] ðŸš€ [Attempt $attempt] Innertube $clientName client...');
          final body = json.encode({
            'context': {'client': clientContext},
            'videoId': video.videoId,
            'playbackContext': {
              'contentPlaybackContext': {
                'html5Preference': 'HTML5_PREF_WANTS',
                'signatureTimestamp': 19800,
              }
            }
          });

          final resp = await httpClient.post(
            Uri.parse('https://www.youtube.com/youtubei/v1/player'),
            headers: {
              'User-Agent': userAgent,
              'Content-Type': 'application/json',
            },
            body: body,
          ).timeout(const Duration(seconds: 8));

          if (resp.statusCode == 200) {
            final data = json.decode(resp.body) as Map<String, dynamic>;
            final formats = (data['streamingData']?['adaptiveFormats'] as List?) ?? [];
            final audioStreams = formats.where((f) {
              final mime = f['mimeType'] as String? ?? '';
              return mime.startsWith('audio/') && f['url'] != null;
            }).toList();

            if (audioStreams.isNotEmpty) {
              // Prioritas 1: itag 140 (audio/mp4 m4a AAC) - paling stabil di ExoPlayer Android
              audioStreams.sort((a, b) {
                final aIs140 = (a['itag'] == 140) ? 1 : 0;
                final bIs140 = (b['itag'] == 140) ? 1 : 0;
                if (aIs140 != bIs140) return bIs140.compareTo(aIs140);
                return ((b['bitrate'] as int?) ?? 0).compareTo((a['bitrate'] as int?) ?? 0);
              });

              final chosen = audioStreams.first;
              // Tambah parameter ratebypass agar YouTube CDN tidak reject (403)
              // YouTube Android app selalu kirim parameter ini saat streaming audio
              final rawUrl = chosen['url'] as String;
              final streamUrl = rawUrl.contains('?')
                  ? '$rawUrl&rn=1&rbuf=0&ratebypass=yes'
                  : '$rawUrl?rn=1&rbuf=0&ratebypass=yes';
              final bitrate = chosen['bitrate'];
              final itag = chosen['itag'];
              final mime = chosen['mimeType'];
              
              debugPrint('[Player] ðŸŽ§ Innertube $clientName selected: itag $itag ($mime, $bitrate bps)');

              if (_loadId != currentLoadId) {
                httpClient.close();
                return;
              }

              final mediaItem = _buildMediaItem(video);
              await _audioHandler!.loadUrl(
                streamUrl,
                mediaItem,
                headers: {'User-Agent': userAgent},
              );
              
              if (_loadId != currentLoadId) {
                httpClient.close();
                return;
              }
              
              _audioHandler!.play();
              httpClient.close();
              return; // Sukses!
            }
          }
        } catch (e) {
          debugPrint('[Player] âš ï¸ Innertube $clientName failed: $e');
          lastError = Exception('Innertube $clientName: $e');
        }
      }

      if (attempt < maxAttempts) {
        await Future.delayed(Duration(milliseconds: 300 * attempt));
      }
    }

    httpClient.close();
    debugPrint('[Player] All Innertube failed, trying youtube_explode_dart fallback...');
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(video.videoId);
      final ytAudioStreams = manifest.audioOnly.toList();
      if (ytAudioStreams.isNotEmpty) {
        ytAudioStreams.sort((a, b) => b.bitrate.compareTo(a.bitrate));
        final ytStream = ytAudioStreams.first;
        final ytUrl = ytStream.url.toString();
        debugPrint('[Player] YT-Explode fallback: ${ytStream.codec.mimeType} ${ytStream.bitrate}');
        if (_loadId != currentLoadId) return;
        final mediaItem = _buildMediaItem(video);
        await _audioHandler!.loadUrl(ytUrl, mediaItem);
        if (_loadId != currentLoadId) return;
        _audioHandler!.play();
        return;
      }
    } catch (ytEx) {
      debugPrint('[Player] YT-Explode also failed: $ytEx');
    }
    throw lastError ?? Exception('Gagal memuat stream audio.');
  }

  /// Buat MediaItem dari VideoItem
  MediaItem _buildMediaItem(VideoItem video) {
    return MediaItem(
      id: video.videoId,
      title: video.title,
      artist: video.channelTitle,
      artUri: Uri.parse(video.thumbnailHighRes),
      duration: video.durationSeconds > 0
          ? Duration(seconds: video.durationSeconds)
          : null,
    );
  }

  Future<void> _saveToHistory() async {
    if (_currentVideo == null) return;
    final history = PlayHistory.fromVideoItem(
      _currentVideo!,
      playlistId: _currentPlaylistId,
    );
    await DbService().upsertHistory(history);
    onHistoryUpdated?.call();
  }

  @override
  void dispose() {
    _yt.close();
    super.dispose();
  }
}

