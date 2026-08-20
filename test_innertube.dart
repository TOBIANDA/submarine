import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  print('Testing Innertube Android API extraction...');
  final ua = 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip';
  final videoId = 'dQw4w9WgXcQ';
  
  final resp = await http.post(
    Uri.parse('https://www.youtube.com/youtubei/v1/player'),
    headers: {
      'User-Agent': ua,
      'Content-Type': 'application/json',
    },
    body: json.encode({
      'context': {
        'client': {
          'clientName': 'ANDROID',
          'clientVersion': '20.10.38',
          'androidSdkVersion': 30,
          'userAgent': ua,
          'hl': 'en',
          'gl': 'US',
        }
      },
      'videoId': videoId,
    }),
  );

  print('Innertube response status: ${resp.statusCode}');
  if (resp.statusCode == 200) {
    final data = json.decode(resp.body) as Map<String, dynamic>;
    final formats = (data['streamingData']?['adaptiveFormats'] as List?) ?? [];
    final audioStreams = formats.where((f) {
      final mime = f['mimeType'] as String? ?? '';
      return mime.startsWith('audio/') && f['url'] != null;
    }).toList();

    print('Found audio streams: ${audioStreams.length}');
    if (audioStreams.isNotEmpty) {
      final chosen = audioStreams.first;
      final rawUrl = chosen['url'] as String;
      print('Chosen audio URL: ${rawUrl.substring(0, 60)}...');
      
      // Test downloading first 100KB with User-Agent header (just like ExoPlayer with headers)
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(rawUrl));
      req.headers.set('User-Agent', ua);
      final res = await req.close();
      print('HTTP Stream Response code: ${res.statusCode}');
      if (res.statusCode == 200 || res.statusCode == 206) {
        print('>>> SUCCESS! Innertube URL is 100% functional with User-Agent header! <<<');
      }
    }
  }
}
