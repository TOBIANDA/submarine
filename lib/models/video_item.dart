// lib/models/video_item.dart

class VideoItem {
  final String videoId;
  final String title;
  final String channelId;
  final String channelTitle;
  final String thumbnailUrl;
  final String? channelLogoUrl;
  final int durationSeconds;
  int order;

  VideoItem({
    required this.videoId,
    required this.title,
    this.channelId = '',
    required this.channelTitle,
    required this.thumbnailUrl,
    this.channelLogoUrl,
    required this.durationSeconds,
    this.order = 0,
  });

  String get formattedDuration {
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get thumbnailHighRes =>
      'https://img.youtube.com/vi/$videoId/hqdefault.jpg';

  /// Cek apakah video merupakan single lagu resmi (bukan full album / kompilasi panjang)
  bool get isSingleSong {
    // 1. Durasi lagu normal: antara 45 detik hingga 11 menit (660 detik)
    if (durationSeconds > 0 && (durationSeconds < 45 || durationSeconds > 660)) {
      return false;
    }
    // 2. Filter kata kunci album kompilasi / non-stop
    final lower = title.toLowerCase();
    const blacklist = [
      'full album',
      'album lengkap',
      'kompilasi',
      'compilation',
      '1 hour',
      '2 hour',
      '3 hour',
      '1 jam',
      '2 jam',
      'nonstop',
      'non stop',
      'discography',
      'best songs of',
      'top 50',
      'top 100',
      'podcast',
      'audiobook',
    ];
    for (final kw in blacklist) {
      if (lower.contains(kw)) return false;
    }
    return true;
  }

  Map<String, dynamic> toMap() => {
        'videoId': videoId,
        'title': title,
        'channelId': channelId,
        'channelTitle': channelTitle,
        'thumbnailUrl': thumbnailUrl,
        'channelLogoUrl': channelLogoUrl,
        'durationSeconds': durationSeconds,
        'order': order,
      };

  factory VideoItem.fromMap(Map<String, dynamic> map) => VideoItem(
        videoId: map['videoId'] as String,
        title: map['title'] as String,
        channelId: map['channelId'] as String? ?? '',
        channelTitle: map['channelTitle'] as String,
        thumbnailUrl: map['thumbnailUrl'] as String,
        channelLogoUrl: map['channelLogoUrl'] as String?,
        durationSeconds: map['durationSeconds'] as int? ?? 0,
        order: map['order'] as int? ?? 0,
      );

  /// Parse ISO 8601 duration string (e.g. "PT3M45S") to seconds
  static int parseDuration(String iso) {
    final regex = RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?');
    final match = regex.firstMatch(iso);
    if (match == null) return 0;
    final h = int.tryParse(match.group(1) ?? '0') ?? 0;
    final m = int.tryParse(match.group(2) ?? '0') ?? 0;
    final s = int.tryParse(match.group(3) ?? '0') ?? 0;
    return h * 3600 + m * 60 + s;
  }

  VideoItem copyWith({
    String? videoId,
    String? title,
    String? channelId,
    String? channelTitle,
    String? thumbnailUrl,
    String? channelLogoUrl,
    int? durationSeconds,
    int? order,
  }) =>
      VideoItem(
        videoId: videoId ?? this.videoId,
        title: title ?? this.title,
        channelId: channelId ?? this.channelId,
        channelTitle: channelTitle ?? this.channelTitle,
        thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
        channelLogoUrl: channelLogoUrl ?? this.channelLogoUrl,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        order: order ?? this.order,
      );
}
