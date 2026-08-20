// lib/widgets/background_youtube_player.dart
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/youtube_player_engine.dart';

class BackgroundYoutubePlayer extends StatefulWidget {
  const BackgroundYoutubePlayer({super.key});

  @override
  State<BackgroundYoutubePlayer> createState() => _BackgroundYoutubePlayerState();
}

class _BackgroundYoutubePlayerState extends State<BackgroundYoutubePlayer> {
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: 0.01,
        child: SizedBox(
          width: 50,
          height: 50,
          child: InAppWebView(
            initialSettings: InAppWebViewSettings(
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              javaScriptEnabled: true,
              cacheEnabled: true,
              userAgent:
                  'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
            ),
            onWebViewCreated: (controller) {
              YoutubePlayerEngine().attachController(controller);
            },
          ),
        ),
      ),
    );
  }
}
