// lib/models/playlist.dart
import 'video_item.dart';

class Playlist {
  final String id;
  String title;
  final DateTime createdAt;
  final String source; // 'manual' | 'ai_curated'
  List<VideoItem> items;

  Playlist({
    required this.id,
    required this.title,
    required this.createdAt,
    this.source = 'manual',
    this.items = const [],
  });

  int get totalDurationSeconds =>
      items.fold(0, (sum, item) => sum + item.durationSeconds);

  String get formattedTotalDuration {
    final total = totalDurationSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  String? get coverThumbnail =>
      items.isNotEmpty ? items.first.thumbnailHighRes : null;

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'source': source,
      };

  factory Playlist.fromMap(Map<String, dynamic> map) => Playlist(
        id: map['id'] as String,
        title: map['title'] as String,
        createdAt: DateTime.parse(map['createdAt'] as String),
        source: map['source'] as String? ?? 'manual',
      );

  Playlist copyWith({String? title, List<VideoItem>? items}) => Playlist(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        source: source,
        items: items ?? this.items,
      );
}
