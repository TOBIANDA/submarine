import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

Future<void> main() async {
  print("=== Testing Continuous Chunked Stream in Dart ===");
  final ua = 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip';
  final client = http.Client();
  
  final resp = await client.post(
    Uri.parse('https://www.youtube.com/youtubei/v1/player'),
    headers: {'User-Agent': ua, 'Content-Type': 'application/json'},
    body: json.encode({
      'context': {
        'client': {'clientName': 'ANDROID', 'clientVersion': '20.10.38', 'androidSdkVersion': 30, 'userAgent': ua, 'hl': 'en', 'gl': 'US'}
      },
      'videoId': 'IPXIgEAGe4U'
    })
  );
  
  final data = json.decode(resp.body) as Map<String, dynamic>;
  final formats = (data['streamingData']?['adaptiveFormats'] as List?) ?? [];
  final audioStreams = formats.where((f) => (f['mimeType'] as String? ?? '').startsWith('audio/') && f['url'] != null).toList();
  final chosen = audioStreams.firstWhere((f) => f['itag'] == 140, orElse: () => audioStreams.first);
  final url = chosen['url'] as String;
  final clen = int.tryParse(chosen['contentLength']?.toString() ?? '0') ?? 3181845;
  print("Selected stream: itag ${chosen['itag']}, size: $clen bytes");

  // Create continuous StreamController
  final controller = StreamController<Uint8List>();
  
  // Background chunk feeder
  () async {
    const chunkSize = 512 * 1024;
    int offset = 0;
    try {
      while (offset < clen) {
        final chunkEnd = (offset + chunkSize - 1).clamp(0, clen - 1);
        final chunkUrl = '$url&range=$offset-$chunkEnd';
        final chunkResp = await http.get(Uri.parse(chunkUrl), headers: {'User-Agent': ua});
        
        if (chunkResp.statusCode == 200) {
          controller.add(chunkResp.bodyBytes);
          print("Streamed chunk $offset-$chunkEnd (${chunkResp.bodyBytes.length} bytes)");
          offset = chunkEnd + 1;
        } else {
          print("Chunk error ${chunkResp.statusCode} at $offset-$chunkEnd");
          break;
        }
      }
    } catch (e) {
      controller.addError(e);
    } finally {
      await controller.close();
    }
  }();

  // Consumer (simulating ExoPlayer reading continuous stream)
  int totalReceived = 0;
  await for (final chunk in controller.stream) {
    totalReceived += chunk.length;
  }
  print("=== FINAL RESULT: Received $totalReceived / $clen bytes (${(totalReceived / clen * 100).toStringAsFixed(1)}%) ===");
}
