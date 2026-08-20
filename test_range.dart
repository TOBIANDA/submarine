import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
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

  final data = json.decode(resp.body) as Map<String, dynamic>;
  final formats = (data['streamingData']?['adaptiveFormats'] as List?) ?? [];
  final audioStreams = formats.where((f) {
    final mime = f['mimeType'] as String? ?? '';
    return mime.startsWith('audio/') && f['url'] != null;
  }).toList();

  final chosen = audioStreams.first;
  final streamUrl = chosen['url'] as String;
  print('Stream URL: ${streamUrl.substring(0, 60)}...');

  // Test 1: Standard HttpClient without Range header
  final client1 = HttpClient();
  final req1 = await client1.getUrl(Uri.parse(streamUrl));
  req1.headers.set('User-Agent', ua);
  final res1 = await req1.close();
  print('Test 1 (no Range header): HTTP ${res1.statusCode}');

  // Test 2: Standard HttpClient WITH Range header (like ExoPlayer sends)
  final client2 = HttpClient();
  final req2 = await client2.getUrl(Uri.parse(streamUrl));
  req2.headers.set('User-Agent', ua);
  req2.headers.set('Range', 'bytes=0-');
  final res2 = await req2.close();
  print('Test 2 (Range: bytes=0-): HTTP ${res2.statusCode}');

  // Test 3: What if we test with IOS Innertube client instead of ANDROID?
  final iosUa = 'com.google.ios.youtube/19.45.4 (iPhone14,3; U; CPU iOS 17_0 like Mac OS X)';
  final respIos = await http.post(
    Uri.parse('https://www.youtube.com/youtubei/v1/player'),
    headers: {
      'User-Agent': iosUa,
      'Content-Type': 'application/json',
    },
    body: json.encode({
      'context': {
        'client': {
          'clientName': 'IOS',
          'clientVersion': '19.45.4',
          'deviceMake': 'Apple',
          'deviceModel': 'iPhone14,3',
          'userAgent': iosUa,
          'hl': 'en',
          'gl': 'US',
        }
      },
      'videoId': videoId,
    }),
  );
  final dataIos = json.decode(respIos.body) as Map<String, dynamic>;
  final formatsIos = (dataIos['streamingData']?['adaptiveFormats'] as List?) ?? [];
  final audioIos = formatsIos.where((f) {
    final mime = f['mimeType'] as String? ?? '';
    return mime.startsWith('audio/') && f['url'] != null;
  }).toList();
  if (audioIos.isNotEmpty) {
    final chosenIos = audioIos.first;
    final urlIos = chosenIos['url'] as String;
    final clientIos = HttpClient();
    final reqIos = await clientIos.getUrl(Uri.parse(urlIos));
    reqIos.headers.set('User-Agent', iosUa);
    reqIos.headers.set('Range', 'bytes=0-');
    final resIos = await reqIos.close();
    print('Test 3 (IOS client + Range header): HTTP ${resIos.statusCode}');
  }
}
