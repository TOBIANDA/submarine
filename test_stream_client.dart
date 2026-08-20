import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Future<void> main() async {
  final yt = YoutubeExplode();
  print('Fetching manifest for video IPXIgEAGe4U...');
  final manifest = await yt.videos.streamsClient.getManifest('IPXIgEAGe4U');
  final audioStreams = manifest.audioOnly.toList();
  print('Found ${audioStreams.length} audio streams:');
  for (final s in audioStreams) {
    print('Tag: ${s.tag}, container: ${s.container.name}, size: ${s.size.totalBytes}, bitrate: ${s.bitrate}');
  }
  
  // Test downloading audio stream directly via StreamsClient
  final chosen = audioStreams.first;
  print('\nTesting yt.videos.streamsClient.get(chosen)...');
  final stream = yt.videos.streamsClient.get(chosen);
  int bytes = 0;
  final sw = Stopwatch()..start();
  try {
    await for (final chunk in stream) {
      bytes += chunk.length;
      if (sw.elapsedMilliseconds > 1000) {
        print('Received ${(bytes/1024).toStringAsFixed(0)} KB / ${(chosen.size.totalBytes/1024).toStringAsFixed(0)} KB');
        sw.reset();
      }
      if (bytes >= chosen.size.totalBytes || bytes >= 3000000) {
        print('SUCCESS! Received $bytes bytes via StreamsClient!');
        break;
      }
    }
  } catch (e) {
    print('Error during stream download: $e');
  }
  yt.close();
}
