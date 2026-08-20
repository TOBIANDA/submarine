// lib/widgets/youtube_background_player.dart
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

class YoutubeBackgroundPlayer extends StatefulWidget {
  final YoutubePlayerController controller;
  final ValueChanged<YoutubeMetaData>? onEnded;

  const YoutubeBackgroundPlayer({
    super.key,
    required this.controller,
    this.onEnded,
  });

  @override
  State<YoutubeBackgroundPlayer> createState() => _YoutubeBackgroundPlayerState();
}

class _YoutubeBackgroundPlayerState extends State<YoutubeBackgroundPlayer> {
  YoutubePlayerController get controller => widget.controller;
  bool _isReady = false;

  static const String _html = '''<!DOCTYPE html>
<html>
<head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <style>
        html, body {
            margin: 0;
            padding: 0;
            width: 100%;
            height: 100%;
            background-color: #000000;
            overflow: hidden;
        }
        #player {
            width: 100%;
            height: 100%;
            pointer-events: none;
        }
    </style>
</head>
<body>
    <div id="player"></div>
    <script>
        // Anti Background Pause & Screen Off Freeze
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
        var timerId;
        function onYouTubeIframeAPIReady() {
            player = new YT.Player('player', {
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
        
        function play() { try { if (player) player.playVideo(); } catch(e) {} return ""; }
        function pause() { try { if (player) player.pauseVideo(); } catch(e) {} return ""; }
        function loadById(loadSettings) { try { if (player) { player.loadVideoById(loadSettings); player.playVideo(); } } catch(e) {} return ""; }
        function cueById(cueSettings) { try { if (player) player.cueVideoById(cueSettings); } catch(e) {} return ""; }
        function mute() { try { if (player) player.mute(); } catch(e) {} return ""; }
        function unMute() { try { if (player) player.unMute(); } catch(e) {} return ""; }
        function setVolume(v) { try { if (player) player.setVolume(v); } catch(e) {} return ""; }
        function seekTo(p, a) { try { if (player) player.seekTo(p, a); } catch(e) {} return ""; }
        function setSize(w, h) { try { if (player) player.setSize(w, h); } catch(e) {} return ""; }
        function setPlaybackRate(r) { try { if (player) player.setPlaybackRate(r); } catch(e) {} return ""; }
    </script>
</body>
</html>''';

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      child: InAppWebView(
        key: widget.key,
        initialData: InAppWebViewInitialData(
          data: _html,
          baseUrl: WebUri.uri(Uri.https('www.youtube-nocookie.com')),
          mimeType: 'text/html',
          encoding: 'utf-8',
        ),
        initialSettings: InAppWebViewSettings(
          userAgent: 'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          mediaPlaybackRequiresUserGesture: false,
          transparentBackground: true,
          disableContextMenu: true,
          supportZoom: false,
          disableHorizontalScroll: true,
          disableVerticalScroll: true,
          allowsInlineMediaPlayback: true,
          allowsAirPlayForMediaPlayback: true,
          allowsPictureInPictureMediaPlayback: true,
          useWideViewPort: false,
          useHybridComposition: false,
        ),
        onWebViewCreated: (webController) {
          controller.updateValue(
            controller.value.copyWith(webViewController: webController),
          );
          webController
            ..addJavaScriptHandler(
              handlerName: 'Ready',
              callback: (_) {
                _isReady = true;
                controller.updateValue(
                  controller.value.copyWith(isReady: true),
                );
              },
            )
            ..addJavaScriptHandler(
              handlerName: 'StateChange',
              callback: (args) {
                final state = args.first as int;
                switch (state) {
                  case -1:
                    controller.updateValue(
                      controller.value.copyWith(
                        playerState: PlayerState.unStarted,
                        isLoaded: true,
                      ),
                    );
                    break;
                  case 0:
                    widget.onEnded?.call(controller.metadata);
                    controller.updateValue(
                      controller.value.copyWith(
                        playerState: PlayerState.ended,
                      ),
                    );
                    break;
                  case 1:
                    controller.updateValue(
                      controller.value.copyWith(
                        playerState: PlayerState.playing,
                        isPlaying: true,
                        hasPlayed: true,
                        errorCode: 0,
                      ),
                    );
                    break;
                  case 2:
                    controller.updateValue(
                      controller.value.copyWith(
                        playerState: PlayerState.paused,
                        isPlaying: false,
                      ),
                    );
                    break;
                  case 3:
                    controller.updateValue(
                      controller.value.copyWith(
                        playerState: PlayerState.buffering,
                      ),
                    );
                    break;
                  case 5:
                    controller.updateValue(
                      controller.value.copyWith(
                        playerState: PlayerState.cued,
                      ),
                    );
                    break;
                }
              },
            )
            ..addJavaScriptHandler(
              handlerName: 'VideoData',
              callback: (args) {
                final data = args.first as Map;
                controller.updateValue(
                  controller.value.copyWith(
                    metaData: YoutubeMetaData(
                      videoId: data['videoId'] ?? '',
                      title: data['title'] ?? '',
                      author: data['author'] ?? '',
                      duration: Duration(seconds: ((data['duration'] ?? 0) as num).toInt()),
                    ),
                  ),
                );
              },
            )
            ..addJavaScriptHandler(
              handlerName: 'VideoTime',
              callback: (args) {
                final num position = args.first;
                final num buffered = args.last;
                controller.updateValue(
                  controller.value.copyWith(
                    position: Duration(milliseconds: (position * 1000).toInt()),
                    buffered: buffered.toDouble(),
                  ),
                );
              },
            );
        },
        onLoadStop: (webController, uri) {
          if (_isReady) {
            controller.updateValue(
              controller.value.copyWith(isReady: true),
            );
          }
        },
      ),
    );
  }
}
