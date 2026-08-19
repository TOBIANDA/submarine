import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Future<void> main() async {
  final yt = YoutubeExplode();
  final manifest = await yt.videos.streamsClient.getManifest('CJdcMHBMBfs');
  final chosen = manifest.audioOnly.firstWhere((f) => f.tag == 140, orElse: () => manifest.audioOnly.first);
  final url = '${chosen.url}&ratebypass=yes&rn=1&rbuf=0';
  final clen = chosen.size.totalBytes;
  final ua = 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip';
  print('Testing Android UA with ratebypass...');

  final client = http.Client();
  const chunkSize = 512 * 1024;
  int total = 0;
  bool success = true;

  for (int chunkIdx = 0; chunkIdx < 10; chunkIdx++) {
    final s = chunkIdx * chunkSize;
    final e = (s + chunkSize - 1).clamp(0, clen - 1);
    if (s >= clen) break;

    final resp = await client.get(Uri.parse(url), headers: {
      'Range': 'bytes=$s-$e',
      'User-Agent': ua,
    });

    print('Chunk $chunkIdx ($s-$e): status=${resp.statusCode}, len=${resp.bodyBytes.length}');
    if (resp.statusCode != 206 && resp.statusCode != 200) {
      success = false;
      break;
    }
    total += resp.bodyBytes.length;
  }

  if (success) {
    print('===> 100% UNTHROTTLED SUCCESS! Downloaded $total / $clen bytes without 403!');
  }
  yt.close();
  client.close();
}
