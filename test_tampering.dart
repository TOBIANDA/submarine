import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  final ua = 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip';
  final videoId = 'dQw4w9WgXcQ';
  
  final resp = await http.post(
    Uri.parse('https://www.youtube.com/youtubei/v1/player'),
    headers: {'User-Agent': ua, 'Content-Type': 'application/json'},
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
  final audio = formats.where((f) => (f['mimeType'] as String? ?? '').startsWith('audio/') && f['url'] != null).first;
  final rawUrl = audio['url'] as String;

  // Test 1: Modified URL with ratebypass
  final modUrl = '$rawUrl&rn=1&rbuf=0&ratebypass=yes';
  final client1 = HttpClient();
  final req1 = await client1.getUrl(Uri.parse(modUrl));
  req1.headers.set('User-Agent', ua);
  final res1 = await req1.close();
  print('With &ratebypass=yes: HTTP ${res1.statusCode}');

  // Test 2: PURE RAW URL without any tampering
  final client2 = HttpClient();
  final req2 = await client2.getUrl(Uri.parse(rawUrl));
  req2.headers.set('User-Agent', ua);
  final res2 = await req2.close();
  print('PURE RAW URL: HTTP ${res2.statusCode}');
}
