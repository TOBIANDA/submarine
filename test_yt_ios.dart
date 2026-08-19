import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:youtube_explode_dart/src/videos/youtube_api_client.dart';
import 'dart:io';

void main() async {
  final yt = YoutubeExplode();
  final videoId = 'dQw4w9WgXcQ';
  try {
    print('Fetching manifest using ios client...');
    final manifest = await yt.videos.streamsClient.getManifest(videoId, ytClients: [YoutubeApiClient.ios]);
    final url = manifest.audioOnly.withHighestBitrate().url.toString();
    
    print('Testing HTTP GET on stream URL WITHOUT headers...');
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    print('Status code: ${res.statusCode}');
    
    int downloaded = 0;
    int startTime = DateTime.now().millisecondsSinceEpoch;
    
    await for (var chunk in res) {
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
