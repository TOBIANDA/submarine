import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'dart:io';

void main() async {
  final yt = YoutubeExplode();
  final videoId = 'dQw4w9WgXcQ';
  try {
    print('Fetching manifest...');
    final manifest = await yt.videos.streamsClient.getManifest(videoId);
    final streamInfo = manifest.audioOnly.withHighestBitrate();
    
    print('Testing yt.videos.streamsClient.get...');
    final stream = yt.videos.streamsClient.get(streamInfo);
    
    int downloaded = 0;
    int startTime = DateTime.now().millisecondsSinceEpoch;
    
    await for (var chunk in stream) {
      downloaded += chunk.length;
      if (downloaded > 1024 * 1024) { // Download 1 MB
        print('Successfully downloaded 1MB in ${DateTime.now().millisecondsSinceEpoch - startTime} ms!');
        break;
      }
    }
  } catch (e) {
    print('Error: $e');
  } finally {
    yt.close();
    exit(0);
  }
}
