import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:youtube_explode_dart/src/videos/youtube_api_client.dart';
import 'dart:io';

Future<void> testClient(YoutubeExplode yt, YoutubeApiClient client, String name) async {
  print('\n--- Testing $name ---');
  try {
    final manifest = await yt.videos.streamsClient.getManifest('dQw4w9WgXcQ', ytClients: [client]);
    if (manifest.muxed.isEmpty) {
      print('No muxed streams found.');
      return;
    }
    final url = manifest.muxed.withHighestBitrate().url.toString();
    
    final httpClient = HttpClient();
    final req = await httpClient.getUrl(Uri.parse(url));
    final res = await req.close();
    print('Status: ${res.statusCode}');
    
    int downloaded = 0;
    int startTime = DateTime.now().millisecondsSinceEpoch;
    
    await for (var chunk in res) {
      downloaded += chunk.length;
      if (downloaded >= 512 * 1024) { // Download 512 KB to be faster
        final timeMs = DateTime.now().millisecondsSinceEpoch - startTime;
        print('Downloaded 512KB in $timeMs ms (${(512 * 1024 / (timeMs / 1000) / 1024).toStringAsFixed(2)} KB/s)');
        break;
      }
    }
    httpClient.close(force: true);
  } catch (e) {
    print('Error: $e');
  }
}

void main() async {
  final yt = YoutubeExplode();
  await testClient(yt, YoutubeApiClient.ios, 'iOS');
  await testClient(yt, YoutubeApiClient.android, 'Android');
  await testClient(yt, YoutubeApiClient.androidVr, 'Android VR');
  yt.close();
  exit(0);
}
