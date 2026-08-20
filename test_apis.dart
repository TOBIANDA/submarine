import 'dart:convert';
import 'dart:io';

void main() async {
  print('Testing Piped & Invidious API instances for direct audio streaming...');
  
  final instances = [
    'https://pipedapi.kavin.rocks',
    'https://api.piped.privacydev.net',
    'https://piped-api.lunar.icu',
    'https://inv.nadeko.net',
    'https://invidious.nerdvpn.de',
    'https://yt.artemislena.eu',
    'https://invidious.jing.rocks',
  ];

  final videoId = 'dQw4w9WgXcQ';

  for (final inst in instances) {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 4);
      
      final isPiped = inst.contains('piped');
      final uri = isPiped 
          ? Uri.parse('$inst/streams/$videoId')
          : Uri.parse('$inst/api/v1/videos/$videoId');
          
      final req = await client.getUrl(uri);
      final res = await req.close();
      
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final json = jsonDecode(body);
        
        if (isPiped) {
          final audioStreams = json['audioStreams'] as List?;
          if (audioStreams != null && audioStreams.isNotEmpty) {
            final best = audioStreams.last;
            print('>>> SUCCESS [$inst] -> Audio URL: ${best['url'].toString().substring(0, 60)}... (bitrate: ${best['bitrate']})');
          }
        } else {
          final formatStreams = json['adaptiveFormats'] as List?;
          if (formatStreams != null) {
            final audio = formatStreams.where((f) => f['type']?.toString().startsWith('audio/') ?? false).toList();
            if (audio.isNotEmpty) {
              final best = audio.first;
              print('>>> SUCCESS [$inst] -> Audio URL: ${best['url'].toString().substring(0, 60)}... (bitrate: ${best['bitrate']})');
            }
          }
        }
      } else {
        print('[$inst] Status ${res.statusCode}');
      }
      client.close();
    } catch (e) {
      final str = e.toString();
      print('[$inst] Error: ${str.substring(0, (str.length < 60 ? str.length : 60))}');
    }
  }
}
