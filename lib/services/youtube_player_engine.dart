// lib/services/youtube_player_engine.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class YoutubePlayerEngine {
  static YoutubePlayerEngine? _instance;
  YoutubePlayerEngine._();
  factory YoutubePlayerEngine() => _instance ??= YoutubePlayerEngine._();

  InAppWebViewController? _controller;
  String? _pendingVideoId;
  String? _currentLoadedId;

  // Callbacks
  Function(Duration position, Duration duration)? onProgress;
  Function(bool isPlaying)? onPlaybackStateChanged;
  VoidCallback? onEnded;

  void attachController(InAppWebViewController controller) {
    _controller = controller;
    debugPrint('[YT-Engine] Attached WebViewController to Background Engine');

    controller.addJavaScriptHandler(
      handlerName: 'onPlayerReady',
      callback: (args) {
        debugPrint('[YT-Engine] YouTube HTML5 Player is READY');
        if (_pendingVideoId != null && _pendingVideoId != _currentLoadedId) {
          final id = _pendingVideoId!;
          _pendingVideoId = null;
          loadVideo(id);
        } else {
          play();
        }
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'onPlayerStateChange',
      callback: (args) {
        final state = args[0] as int?;
        debugPrint('[YT-Engine] State change: $state');
        // 1 = PLAYING, 2 = PAUSED, 0 = ENDED, 3 = BUFFERING
        if (state == 1) {
          onPlaybackStateChanged?.call(true);
        } else if (state == 2) {
          onPlaybackStateChanged?.call(false);
        } else if (state == 0) {
          onPlaybackStateChanged?.call(false);
          onEnded?.call();
        }
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'onPlayerProgress',
      callback: (args) {
        if (args.isNotEmpty && args[0] is Map) {
          final map = Map<String, dynamic>.from(args[0] as Map);
          final cur = (map['currentTime'] as num?)?.toDouble() ?? 0.0;
          final dur = (map['duration'] as num?)?.toDouble() ?? 0.0;
          onProgress?.call(
            Duration(milliseconds: (cur * 1000).toInt()),
            Duration(milliseconds: (dur * 1000).toInt()),
          );
        }
      },
    );
  }

  String _buildHtml(String videoId) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body { margin:0; padding:0; background:black; }
    #player { width:100%; height:100%; }
  </style>
</head>
<body>
  <div id="player"></div>
  <script>
    // Anti Background Pause & Visibility Spoofing
    try {
      Object.defineProperty(document, 'hidden', { value: false, writable: false });
      Object.defineProperty(document, 'visibilityState', { value: 'visible', writable: false });
      document.addEventListener('visibilitychange', function(e) { e.stopImmediatePropagation(); }, true);
      window.addEventListener('blur', function(e) { e.stopImmediatePropagation(); }, true);
      window.addEventListener('pagehide', function(e) { e.stopImmediatePropagation(); }, true);
    } catch(e) {}

    var tag = document.createElement('script');
    tag.src = "https://www.youtube.com/iframe_api";
    var firstScriptTag = document.getElementsByTagName('script')[0];
    firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);

    var player;
    function onYouTubeIframeAPIReady() {
      player = new YT.Player('player', {
        height: '100%',
        width: '100%',
        videoId: '$videoId',
        playerVars: {
          'autoplay': 1,
          'playsinline': 1,
          'controls': 0,
          'rel': 0,
          'enablejsapi': 1,
          'origin': 'https://www.youtube.com',
          'widget_referrer': 'https://www.youtube.com'
        },
        events: {
          'onReady': function(e) {
            window.flutter_inappwebview.callHandler('onPlayerReady');
            e.target.playVideo();
          },
          'onStateChange': function(e) {
            window.flutter_inappwebview.callHandler('onPlayerStateChange', e.data);
          }
        }
      });

      setInterval(function() {
        try {
          if (player && typeof player.getCurrentTime === 'function' && typeof player.getDuration === 'function') {
            window.flutter_inappwebview.callHandler('onPlayerProgress', {
              'currentTime': player.getCurrentTime(),
              'duration': player.getDuration()
            });
          }
        } catch(e) {}
      }, 500);
    }
  </script>
</body>
</html>
''';
  }

  Future<void> loadVideo(String videoId) async {
    _currentLoadedId = videoId;
    if (_controller == null) {
      debugPrint('[YT-Engine] Controller not yet attached, pending: $videoId');
      _pendingVideoId = videoId;
      return;
    }

    final html = _buildHtml(videoId);
    debugPrint('[YT-Engine] Loading HTML for video $videoId');
    await _controller?.loadData(
      data: html,
      baseUrl: WebUri('https://www.youtube.com'),
      mimeType: 'text/html',
      encoding: 'utf-8',
    );
  }

  Future<void> play() async {
    await _controller?.evaluateJavascript(source: 'if(player && player.playVideo) player.playVideo();');
  }

  Future<void> pause() async {
    await _controller?.evaluateJavascript(source: 'if(player && player.pauseVideo) player.pauseVideo();');
  }

  Future<void> seekTo(Duration position) async {
    final seconds = position.inMilliseconds / 1000.0;
    await _controller?.evaluateJavascript(source: 'if(player && player.seekTo) player.seekTo($seconds, true);');
  }

  Future<void> stop() async {
    _pendingVideoId = null;
    _currentLoadedId = null;
    await _controller?.evaluateJavascript(source: 'if(player && player.stopVideo) player.stopVideo();');
  }
}
