import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() async {
  final videoId = '7Qp5vcuMIlk';
  print('Testing youtube_explode_dart manifest & stream for: $videoId ...');
  
  final yt = YoutubeExplode();
  try {
    final manifest = await yt.videos.streamsClient.getManifest(videoId);
    final audioStreams = manifest.audioOnly;
    print('Found ${audioStreams.length} audio streams!');
    
    for (final s in audioStreams) {
      print('Stream: ${s.container.name}, ${s.bitrate.kiloBitsPerSecond} kbps, itag: ${s.tag}');
    }
    
    final bestAudio = audioStreams.withHighestBitrate();
    print('Testing download stream of best audio: ${bestAudio.url.toString().substring(0, 60)}...');
    
    final stream = yt.videos.streamsClient.get(bestAudio);
    int count = 0;
    await for (final chunk in stream) {
      count += chunk.length;
      if (count > 200000) {
        print('>>> SUCCESS! Received $count bytes from youtube_explode stream! <<<');
        break;
      }
    }
  } catch (e) {
    print('youtube_explode error: $e');
  } finally {
    yt.close();
  }
}
