import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Future<void> main() async {
  final yt = YoutubeExplode();
  final manifest = await yt.videos.streamsClient.getManifest('CJdcMHBMBfs');
  print('Manifest retrieved. Audio streams count: ${manifest.audioOnly.length}');
  for (final a in manifest.audioOnly) {
    print('Tag: ${a.tag}, url: ${a.url.toString().substring(0, 80)}...');
    // Check if url has n parameter
    final uri = a.url;
    print('  n-param in url: ${uri.queryParameters["n"]}');
  }
  yt.close();
}
