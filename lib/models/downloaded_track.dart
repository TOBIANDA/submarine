// lib/models/downloaded_track.dart
import 'video_item.dart';

class DownloadedTrack {
  final String videoId;
  final String title;
  final String channelTitle;
  final String thumbnailUrl;
  final int durationSeconds;
  final String localPath;
  final DateTime downloadedAt;
  final int fileSizeBytes;

  const DownloadedTrack({
    required this.videoId,
    required this.title,
    required this.channelTitle,
    required this.thumbnailUrl,
    required this.durationSeconds,
    required this.localPath,
    required this.downloadedAt,
    required this.fileSizeBytes,
  });

  String get formattedDuration {
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get formattedSize {
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get thumbnailHighRes =>
      'https://img.youtube.com/vi/$videoId/hqdefault.jpg';

  VideoItem toVideoItem() => VideoItem(
        videoId: videoId,
        title: title,
        channelTitle: channelTitle,
        thumbnailUrl: thumbnailUrl,
        durationSeconds: durationSeconds,
      );

  Map<String, dynamic> toMap() => {
        'videoId': videoId,
        'title': title,
        'channelTitle': channelTitle,
        'thumbnailUrl': thumbnailUrl,
        'durationSeconds': durationSeconds,
        'localPath': localPath,
        'downloadedAt': downloadedAt.toIso8601String(),
        'fileSizeBytes': fileSizeBytes,
      };

  factory DownloadedTrack.fromMap(Map<String, dynamic> map) => DownloadedTrack(
        videoId: map['videoId'] as String,
        title: map['title'] as String,
        channelTitle: map['channelTitle'] as String,
        thumbnailUrl: map['thumbnailUrl'] as String,
        durationSeconds: map['durationSeconds'] as int? ?? 0,
        localPath: map['localPath'] as String,
        downloadedAt: DateTime.parse(map['downloadedAt'] as String),
        fileSizeBytes: map['fileSizeBytes'] as int? ?? 0,
      );
}
