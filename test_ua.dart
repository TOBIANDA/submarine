import 'dart:io';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() async {
  final yt = YoutubeExplode();
  final videoId = 'dQw4w9WgXcQ';
  final manifest = await yt.videos.streamsClient.getManifest(videoId);
  final audioStream = manifest.audioOnly.withHighestBitrate();
  final url = audioStream.url;
  print('Stream URL: ${url.toString().substring(0, 60)}...');

  // Test 1: HttpClient WITHOUT headers (like Default ExoPlayer) -> Expect 403
  final client1 = HttpClient();
  final req1 = await client1.getUrl(url);
  final res1 = await req1.close();
  print('Test 1 (No headers): HTTP ${res1.statusCode}');

  // Test 2: HttpClient WITH User-Agent header (like ExoPlayer with headers) -> Expect 200/206
  final client2 = HttpClient();
  final req2 = await client2.getUrl(url);
  req2.headers.set('User-Agent', 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip');
  final res2 = await req2.close();
  print('Test 2 (With Android UA header): HTTP ${res2.statusCode}');

  // Test 3: HttpClient WITH Browser User-Agent header
  final client3 = HttpClient();
  final req3 = await client3.getUrl(url);
  req3.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');
  final res3 = await req3.close();
  print('Test 3 (With Browser UA header): HTTP ${res3.statusCode}');

  yt.close();
}
