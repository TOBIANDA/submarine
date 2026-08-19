import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final videoId = 'dQw4w9WgXcQ';
  final instances = [
    'https://vid.puffyan.us',
    'https://invidious.slipfox.xyz',
    'https://inv.tux.pizza',
    'https://invidious.protokolla.fi',
    'https://iv.melmac.space',
    'https://invidious.perennialte.ch',
  ];
  
  for (final baseUrl in instances) {
    print('\nTesting Invidious $baseUrl...');
    final apiUrl = '$baseUrl/api/v1/videos/$videoId';
    try {
      final response = await http.get(Uri.parse(apiUrl)).timeout(Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final adaptiveFormats = data['adaptiveFormats'] as List?;
        if (adaptiveFormats != null && adaptiveFormats.isNotEmpty) {
          final audioStreams = adaptiveFormats.where((f) => (f['type'] ?? '').contains('audio/')).toList();
          audioStreams.sort((a, b) => (b['bitrate'] ?? 0).compareTo(a['bitrate'] ?? 0));
          final bestAudio = audioStreams.first;
          print('Success at $baseUrl!');
          print('URL: ${bestAudio['url']}');
          break; // Stop after first success
        } else {
           print('No adaptiveFormats found');
        }
      } else {
        print('Failed: ${response.statusCode}');
      }
    } catch (e) {
      print('Error: $e');
    }
  }
}
