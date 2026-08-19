import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'dart:io';

void main() async {
  final yt = YoutubeExplode();
  final videoId = 'dQw4w9WgXcQ'; // Rick roll
  print('Fetching manifest for $videoId');
  try {
    final manifest = await yt.videos.streamsClient.getManifest(videoId);
    final audioStreams = manifest.audioOnly;
    final streamInfo = audioStreams.withHighestBitrate();
    final url = streamInfo.url.toString();
    print('Stream URL: $url');
    
    // Test the URL with HttpClient
    print('Testing HTTP GET on stream URL...');
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
    final res = await req.close();
    print('Status code: ${res.statusCode}');
    
    if (res.statusCode == 200) {
      print('URL is working and returned HTTP 200!');
    } else {
      print('URL failed! Status code: ${res.statusCode}');
    }
  } catch (e) {
    print('Error: $e');
  } finally {
    yt.close();
    exit(0);
  }
}
