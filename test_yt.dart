import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() async {
  final yt = YoutubeExplode();
  try {
    print('Fetching stream info for video...');
    final manifest = await yt.videos.streamsClient.getManifest('OT5msu-dap8');
    final audioStream = manifest.audioOnly.withHighestBitrate();
    print('Stream URL: ${audioStream.url}');
  } catch (e) {
    print('Error: $e');
  } finally {
    yt.close();
  }
}
