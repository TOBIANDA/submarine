import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'dart:io';

void main() async {
  final yt = YoutubeExplode();
  final videoId = 'dQw4w9WgXcQ';
  try {
    final manifest = await yt.videos.streamsClient.getManifest(videoId);
    for (var s in manifest.audioOnly) {
      print('AudioStream: url=${s.url}, audioCodec=${s.audioCodec}, container=${s.container.name}, size=${s.size}');
    }
  } catch (e) {
    print('Error: $e');
  } finally {
    yt.close();
    exit(0);
  }
}
