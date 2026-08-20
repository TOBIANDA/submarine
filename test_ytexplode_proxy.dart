import 'dart:convert';
import 'dart:io';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() async {
  final videoId = '7Qp5vcuMIlk';
  print('Testing YoutubeExplode piped into local HTTP server for: $videoId ...');

  final yt = YoutubeExplode();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  print('Server listening on port ${server.port}');

  server.listen((HttpRequest req) async {
    print('Proxy got request: ${req.uri}');
    try {
      final manifest = await yt.videos.streamsClient.getManifest(videoId);
      final audioStreams = manifest.audioOnly;
      final bestAudio = audioStreams.withHighestBitrate();
      
      print('Selected stream: ${bestAudio.container.name}, size: ${bestAudio.size.totalBytes}');
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.parse('audio/${bestAudio.container.name}');
      req.response.headers.set('Content-Length', bestAudio.size.totalBytes.toString());
      req.response.headers.set('Accept-Ranges', 'none');

      final stream = yt.videos.streamsClient.get(bestAudio);
      await req.response.addStream(stream);
      await req.response.close();
      print('Proxy finished streaming!');
    } catch (e) {
      print('Proxy error: $e');
      req.response.statusCode = HttpStatus.internalServerError;
      await req.response.close();
    }
  });

  // Test client connecting to proxy
  final client = HttpClient();
  final req = await client.getUrl(Uri.parse('http://127.0.0.1:${server.port}/stream'));
  final res = await req.close();
  print('Client received response code: ${res.statusCode}');
  print('Content-Length: ${res.contentLength}');

  int total = 0;
  await for (final chunk in res) {
    total += chunk.length;
    if (total > 300000) {
      print('>>> SUCCESS! Received $total bytes seamlessly from proxy! <<<');
      break;
    }
  }

  await server.close();
  yt.close();
}
