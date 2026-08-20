import 'dart:convert';
import 'dart:io';

void main() async {
  print('Testing Piped APIs for direct clean audio URL...');
  final instances = [
    'https://pipedapi.kavin.rocks',
    'https://api.piped.privacydev.net',
    'https://piped-api.lunar.icu',
    'https://yt.artemislena.eu',
    'https://invidious.nerdvpn.de',
  ];
  final videoId = 'OT5msu-dap8';

  for (final inst in instances) {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 4);
      final isPiped = inst.contains('piped');
      final uri = isPiped ? Uri.parse('$inst/streams/$videoId') : Uri.parse('$inst/api/v1/videos/$videoId');
      final req = await client.getUrl(uri);
      final res = await req.close();
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final json = jsonDecode(body);
        if (isPiped) {
          final audioStreams = json['audioStreams'] as List?;
          if (audioStreams != null && audioStreams.isNotEmpty) {
            final best = audioStreams.last;
            final audioUrl = best['url'] as String;
            print('SUCCESS [$inst] Audio: ${audioUrl.substring(0, 50)}...');

            // Test if ExoPlayer can open this URL directly without headers
            final testClient = HttpClient();
            final testReq = await testClient.getUrl(Uri.parse(audioUrl));
            final testRes = await testReq.close();
            print('  -> Direct audio URL HTTP Status: ${testRes.statusCode} (Length: ${testRes.contentLength})');
            testClient.close();
            client.close();
            return;
          }
        }
      }
      client.close();
    } catch (e) {
      print('[$inst] Error: $e');
    }
  }
}
