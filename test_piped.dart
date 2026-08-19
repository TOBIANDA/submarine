import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final videoId = 'dQw4w9WgXcQ';
  final instances = [
    'https://pipedapi.kavin.rocks',
    'https://pipedapi.tokhmi.xyz',
    'https://pipedapi.syncpundit.io',
    'https://api.piped.projectsegfau.lt',
    'https://piped-api.garudalinux.org',
    'https://pipedapi.smnz.de',
  ];
  
  for (final baseUrl in instances) {
    print('Testing $baseUrl...');
    final apiUrl = '$baseUrl/streams/$videoId';
    try {
      final response = await http.get(Uri.parse(apiUrl)).timeout(Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final audioStreams = data['audioStreams'] as List;
        if (audioStreams.isNotEmpty) {
          audioStreams.sort((a, b) => (b['bitrate'] ?? 0).compareTo(a['bitrate'] ?? 0));
          final bestAudio = audioStreams.first;
          print('Success at $baseUrl!');
          print('URL: ${bestAudio['url']}');
          print('Bitrate: ${bestAudio['bitrate']}');
          break; // Stop after first success
        }
      } else {
        print('Failed: ${response.statusCode}');
      }
    } catch (e) {
      print('Error: $e');
    }
  }
}
