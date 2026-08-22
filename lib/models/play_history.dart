// lib/models/play_history.dart
import 'video_item.dart';

class PlayHistory {
  final int? id;
  final String videoId;
  final String title;
  final String channelTitle;
  final String thumbnailUrl;
  final int durationSeconds;
  final DateTime playedAt;
  final int lastPositionSeconds;
  final double completionRate;
  final String? playlistId;

  PlayHistory({
    this.id,
    required this.videoId,
    required this.title,
    required this.channelTitle,
    required this.thumbnailUrl,
    required this.durationSeconds,
    required this.playedAt,
    this.lastPositionSeconds = 0,
    this.completionRate = 1.0,
    this.playlistId,
  });

  factory PlayHistory.fromVideoItem(VideoItem item, {String? playlistId}) =>
      PlayHistory(
        videoId: item.videoId,
        title: item.title,
        channelTitle: item.channelTitle,
        thumbnailUrl: item.thumbnailUrl,
        durationSeconds: item.durationSeconds,
        playedAt: DateTime.now(),
        completionRate: 1.0,
        playlistId: playlistId,
      );

  VideoItem toVideoItem() => VideoItem(
        videoId: videoId,
        title: title,
        channelTitle: channelTitle,
        thumbnailUrl: thumbnailUrl,
        durationSeconds: durationSeconds,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'videoId': videoId,
        'title': title,
        'channelTitle': channelTitle,
        'thumbnailUrl': thumbnailUrl,
        'durationSeconds': durationSeconds,
        'playedAt': playedAt.toIso8601String(),
        'lastPositionSeconds': lastPositionSeconds,
        'completionRate': completionRate,
        'playlistId': playlistId,
      };

  factory PlayHistory.fromMap(Map<String, dynamic> map) => PlayHistory(
        id: map['id'] as int?,
        videoId: map['videoId'] as String,
        title: map['title'] as String,
        channelTitle: map['channelTitle'] as String,
        thumbnailUrl: map['thumbnailUrl'] as String,
        durationSeconds: map['durationSeconds'] as int? ?? 0,
        playedAt: DateTime.parse(map['playedAt'] as String),
        lastPositionSeconds: map['lastPositionSeconds'] as int? ?? 0,
        completionRate: (map['completionRate'] as num?)?.toDouble() ?? 1.0,
        playlistId: map['playlistId'] as String?,
      );

  PlayHistory copyWith({int? lastPositionSeconds, double? completionRate}) => PlayHistory(
        id: id,
        videoId: videoId,
        title: title,
        channelTitle: channelTitle,
        thumbnailUrl: thumbnailUrl,
        durationSeconds: durationSeconds,
        playedAt: playedAt,
        lastPositionSeconds: lastPositionSeconds ?? this.lastPositionSeconds,
        completionRate: completionRate ?? this.completionRate,
        playlistId: playlistId,
      );
}
