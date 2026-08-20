// lib/services/youtube_headless_engine.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// YoutubeHeadlessEngine - Runs the official YouTube IFrame Player in a pure
/// headless (in-memory) background WebView.
///
/// 1. NO SurfaceView / GPU texture -> Android NEVER destroys it when app is minimized!
/// 2. Injected JS visibility spoofing -> YouTube player NEVER pauses in background!
/// 3. Zero Mali gralloc memory leaks or screen rendering conflicts.
class YoutubeHeadlessEngine {
  HeadlessInAppWebView? _headless;
  InAppWebViewController? _controller;
  bool _isReady = false;
  String? _pendingVideoId;

  final void Function(int state)? onStateChange;
  final void Function(Duration position, double buffered)? onTimeUpdate;
  final void Function(String title, String author, Duration duration)? onVideoData;
  final void Function()? onEnded;

  YoutubeHeadlessEngine({
    this.onStateChange,
    this.onTimeUpdate,
    this.onVideoData,
    this.onEnded,
  });

  bool get isReady => _isReady;

  static const String _html = '''<!DOCTYPE html>
<html>
<head>
    <meta name="viewport" content="width=device-width,initial-scale=1.0,maximum-scale=1.0,user-scalable=no">
    <script>
        try {
            Object.defineProperty(document, "hidden", { get: () => false, configurable: true });
            Object.defineProperty(document, "visibilityState", { get: () => "visible", configurable: true });
            Object.defineProperty(document, "webkitHidden", { get: () => false, configurable: true });
            Object.defineProperty(document, "webkitVisibilityState", { get: () => "visible", configurable: true });
            document.addEventListener("visibilitychange", (e) => e.stopImmediatePropagation(), true);
            document.addEventListener("webkitvisibilitychange", (e) => e.stopImmediatePropagation(), true);
        } catch(e) {}
    </script>
</head>
<body style="margin:0;padding:0;background-color:#000;">
    <div id="player"></div>
    <script>
        var tag = document.createElement("script");
        tag.src = "https://www.youtube.com/iframe_api";
        var firstScriptTag = document.getElementsByTagName("script")[0];
        firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);
        
        var player;
        var timerId;
        
        function onYouTubeIframeAPIReady() {
            player = new YT.Player("player", {
                height: "100%",
                width: "100%",
                playerVars: {
                    "controls": 0,
                    "playsinline": 1,
                    "enablejsapi": 1,
                    "fs": 0,
                    "rel": 0,
                    "showinfo": 0,
                    "iv_load_policy": 3,
                    "modestbranding": 1,
                    "cc_load_policy": 0,
                    "autoplay": 1,
                    "origin": "https://www.youtube-nocookie.com"
                },
                events: {
                    "onReady": function(e) {
                        window.flutter_inappwebview.callHandler("Ready");
                    },
                    "onStateChange": function(e) {
                        clearTimeout(timerId);
                        window.flutter_inappwebview.callHandler("StateChange", e.data);
                        if (e.data == 1) {
                            startTimer();
                            sendData();
                        }
                    },
                    "onError": function(e) {
                        window.flutter_inappwebview.callHandler("Error", e.data);
                    }
                }
            });
        }
        
        function startTimer() {
            timerId = setInterval(function() {
                try {
                    window.flutter_inappwebview.callHandler("VideoTime", player.getCurrentTime(), player.getVideoLoadedFraction());
                } catch(e) {}
            }, 250);
        }
        
        function sendData() {
            try {
                window.flutter_inappwebview.callHandler("VideoData", {
                    "duration": player.getDuration(),
                    "title": player.getVideoData().title,
                    "author": player.getVideoData().author,
                    "videoId": player.getVideoData().video_id
                });
            } catch(e) {}
        }
        
        function loadById(id) {
            try {
                if (player && player.loadVideoById) {
                    player.loadVideoById(id);
                    player.playVideo();
                }
            } catch(e) {}
        }
        
        function play() { try { if (player) player.playVideo(); } catch(e) {} }
        function pause() { try { if (player) player.pauseVideo(); } catch(e) {} }
        function seekTo(s) { try { if (player) player.seekTo(s, true); } catch(e) {} }
        function setVolume(v) { try { if (player) player.setVolume(v); } catch(e) {} }
    </script>
</body>
</html>''';

  Future<void> init() async {
    if (_headless != null) return;
    debugPrint('[HeadlessEngine] Initializing headless YouTube engine...');
    
    _headless = HeadlessInAppWebView(
      initialData: InAppWebViewInitialData(
        data: _html,
        baseUrl: WebUri.uri(Uri.https('www.youtube-nocookie.com')),
        mimeType: 'text/html',
        encoding: 'utf-8',
      ),
      initialSettings: InAppWebViewSettings(
        userAgent: 'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        allowsAirPlayForMediaPlayback: true,
        allowsPictureInPictureMediaPlayback: true,
        transparentBackground: true,
      ),
      onWebViewCreated: (ctrl) {
        _controller = ctrl;
        ctrl.addJavaScriptHandler(
          handlerName: 'Ready',
          callback: (_) {
            debugPrint('[HeadlessEngine] YouTube IFrame API Ready!');
            _isReady = true;
            if (_pendingVideoId != null) {
              final id = _pendingVideoId!;
              _pendingVideoId = null;
              loadVideo(id);
            }
          },
        );
        ctrl.addJavaScriptHandler(
          handlerName: 'StateChange',
          callback: (args) {
            final state = args.first as int;
            onStateChange?.call(state);
            if (state == 0) onEnded?.call();
          },
        );
        ctrl.addJavaScriptHandler(
          handlerName: 'VideoTime',
          callback: (args) {
            final num pos = args.first;
            final num buf = args.last;
            onTimeUpdate?.call(
              Duration(milliseconds: (pos * 1000).toInt()),
              buf.toDouble(),
            );
          },
        );
        ctrl.addJavaScriptHandler(
          handlerName: 'VideoData',
          callback: (args) {
            final data = args.first as Map;
            onVideoData?.call(
              data['title'] ?? '',
              data['author'] ?? '',
              Duration(seconds: ((data['duration'] ?? 0) as num).toInt()),
            );
          },
        );
      },
    );

    await _headless?.run();
  }

  void loadVideo(String videoId) {
    if (!_isReady) {
      _pendingVideoId = videoId;
      return;
    }
    debugPrint('[HeadlessEngine] Loading video $videoId in headless engine');
    _controller?.evaluateJavascript(source: 'loadById("$videoId");');
  }

  void play() {
    _controller?.evaluateJavascript(source: 'play();');
  }

  void pause() {
    _controller?.evaluateJavascript(source: 'pause();');
  }

  void seekTo(Duration position) {
    _controller?.evaluateJavascript(source: 'seekTo(${position.inSeconds});');
  }

  void setVolume(int volume) {
    _controller?.evaluateJavascript(source: 'setVolume($volume);');
  }

  void dispose() {
    _headless?.dispose();
    _headless = null;
    _controller = null;
    _isReady = false;
  }
}
