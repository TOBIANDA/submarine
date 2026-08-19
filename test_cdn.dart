import 'dart:convert';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final ua = 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip';
  
  print('=== TEST: Fetching Innertube URL ===');
  final resp = await http.post(
    Uri.parse('https://www.youtube.com/youtubei/v1/player'),
    headers: {'User-Agent': ua, 'Content-Type': 'application/json'},
    body: jsonEncode({
      'context': {'client': {
        'clientName': 'ANDROID', 'clientVersion': '20.10.38',
        'androidSdkVersion': 30, 'userAgent': ua, 'hl': 'en', 'gl': 'US',
      }},
      'videoId': 'CJdcMHBMBfs',
    }),
  );
  
  final data = jsonDecode(resp.body);
  final formats = (data['streamingData']?['adaptiveFormats'] as List? ?? []);
  final audio = formats.where((f) => (f['mimeType'] as String? ?? '').startsWith('audio/') && f['url'] != null).toList();
  final f140 = audio.firstWhere((f) => f['itag'] == 140, orElse: () => audio.first);
  
  final url = f140['url'] as String;
  print('Got URL (first 120): ${url.substring(0, 120)}');
  
  print('=== TEST: Fetching CDN URL with Range ===');
  final resp2 = await http.get(
    Uri.parse(url),
    headers: {'User-Agent': ua, 'Range': 'bytes=0-1023'},
  );
  print('CDN Status: ${resp2.statusCode}');
  print('CDN Content-Type: ${resp2.headers["content-type"]}');
  print('CDN Content-Range: ${resp2.headers["content-range"]}');
  print('CDN Body length: ${resp2.bodyBytes.length}');
}
