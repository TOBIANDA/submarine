// lib/providers/recommendation_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/video_item.dart';
import '../services/db_service.dart';
import '../services/youtube_service.dart';

/// Kategori konten ala GoTube
enum HomeCategory {
  all,
  trending,
  music,
  gaming,
  news,
  live,
}

extension HomeCategoryExtension on HomeCategory {
  String get label {
    switch (this) {
      case HomeCategory.all:
        return 'Semua';
      case HomeCategory.trending:
        return 'Trending';
      case HomeCategory.music:
        return 'Musik';
      case HomeCategory.gaming:
        return 'Gaming';
      case HomeCategory.news:
        return 'Berita';
      case HomeCategory.live:
        return 'Live';
    }
  }

  String get searchQuery {
    switch (this) {
      case HomeCategory.all:
        return '';
      case HomeCategory.trending:
        return 'trending indonesia 2025';
      case HomeCategory.music:
        return 'musik indonesia terbaru 2025';
      case HomeCategory.gaming:
        return 'gaming highlights indonesia';
      case HomeCategory.news:
        return 'berita hari ini indonesia';
      case HomeCategory.live:
        return 'live streaming indonesia';
    }
  }
}

// Provider untuk kategori aktif
final activeCategoryProvider = StateProvider<HomeCategory>((ref) => HomeCategory.all);

// Provider rekomendasi berdasarkan kategori
final recommendationProvider = FutureProvider.autoDispose<List<VideoItem>>((ref) async {
  final category = ref.watch(activeCategoryProvider);
  final ytService = YoutubeService();
  final dbService = DbService();

  switch (category) {
    case HomeCategory.all:
      // Gunakan history-based recommendation (perilaku asal)
      final lastPlayed = await dbService.getLastPlayed();
      if (lastPlayed != null) {
        final seedVideo = VideoItem(
          videoId: lastPlayed.videoId,
          title: lastPlayed.title,
          channelTitle: lastPlayed.channelTitle,
          thumbnailUrl: lastPlayed.thumbnailUrl,
          durationSeconds: lastPlayed.durationSeconds,
        );
        try {
          final related = await ytService.getRelatedVideos(seedVideo, maxResults: 15);
          if (related.isNotEmpty) return related;
        } catch (_) {
          // fallthrough ke trending
        }
      }
      return ytService.getTrendingVideos(maxResults: 15);

    case HomeCategory.trending:
      return ytService.getTrendingVideos(maxResults: 15);

    case HomeCategory.music:
    case HomeCategory.gaming:
    case HomeCategory.news:
    case HomeCategory.live:
      return ytService.searchVideos(category.searchQuery, maxResults: 15);
  }
});
