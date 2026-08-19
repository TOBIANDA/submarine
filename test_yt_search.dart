import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() async {
  final yt = YoutubeExplode();
  
  try {
    print('Searching...');
    final results = await yt.search.search('Ado Usseewa');
    print('Found ${results.length} results');
    
    for (final video in results.take(2)) {
      print('---');
      print('Title: ${video.title}');
      print('Author: ${video.author}');
      print('Duration: ${video.duration}');
      print('Video ID: ${video.id.value}');
      print('Thumbnail: ${video.thumbnails.mediumResUrl}');
    }
  } catch (e) {
    print('Error: $e');
  } finally {
    yt.close();
  }
}
