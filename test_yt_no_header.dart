import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'dart:io';

void main() async {
  final yt = YoutubeExplode();
  final videoId = 'dQw4w9WgXcQ'; // Rick roll
  try {
    final manifest = await yt.videos.streamsClient.getManifest(videoId);
    final url = manifest.audioOnly.withHighestBitrate().url.toString();
    
    print('Testing HTTP GET on stream URL WITHOUT headers...');
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(url));
    // No headers!
    final res = await req.close();
    print('Status code: ${res.statusCode}');
  } catch (e) {
    print('Error: $e');
  } finally {
    yt.close();
    exit(0);
  }
}
