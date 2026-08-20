import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  final videoId = '7Qp5vcuMIlk';
  print('Testing Piped & Invidious instances for video: $videoId ...');

  final instances = [
    'https://pipedapi.kavin.rocks',
    'https://api.piped.privacydev.net',
    'https://piped-api.lunar.icu',
    'https://inv.nadeko.net',
    'https://invidious.nerdvpn.de',
    'https://yt.artemislena.eu',
    'https://invidious.jing.rocks',
    'https://invidious.drgns.space',
    'https://invidious.projectsegfau.lt',
  ];

  for (final inst in instances) {
    try {
      final isPiped = inst.contains('piped');
      final uri = isPiped
          ? Uri.parse('$inst/streams/$videoId')
          : Uri.parse('$inst/api/v1/videos/$videoId');

      final resp = await http.get(uri).timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        String? audioUrl;
        if (isPiped) {
          final streams = data['audioStreams'] as List?;
          if (streams != null && streams.isNotEmpty) {
            audioUrl = streams.last['url'] as String?;
          }
        } else {
          final formats = data['adaptiveFormats'] as List?;
          if (formats != null) {
            final audio = formats.where((f) => (f['type']?.toString() ?? '').startsWith('audio/')).toList();
            if (audio.isNotEmpty) {
              audioUrl = audio.first['url'] as String?;
            }
          }
        }

        if (audioUrl != null && audioUrl.isNotEmpty) {
          print('>>> SUCCESS [$inst] URL found!');
          // Test downloading from audioUrl
          final req = http.Request('GET', Uri.parse(audioUrl));
          final streamed = await http.Client().send(req);
          print('  -> HTTP Status: ${streamed.statusCode}');
          if (streamed.statusCode == 200 || streamed.statusCode == 206) {
            print('  >>> WINNER! [$inst] Streams perfectly without 403! <<<');
          }
        }
      }
    } catch (e) {
      // ignore
    }
  }
}
