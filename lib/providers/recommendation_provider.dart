// lib/providers/recommendation_provider.dart
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/video_item.dart';
import '../services/db_service.dart';
import '../services/recommendation_service.dart';
import '../services/youtube_service.dart';

/// Kategori konten ala GoTube / Spotify
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
        return 'top hits indonesia 2025 official audio';
      case HomeCategory.music:
        return 'pop indonesia official audio 2025';
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

// 🎵 Daily Mix Provider (Last.fm Graph ML + On-Device Affinity Scoring + 24h SQLite Cache) 🎵
final dailyMixProvider = FutureProvider.autoDispose<List<VideoItem>>((ref) async {
  final dbService = DbService();
  final recommender = RecommendationService();

  // 1. Check local SQLite cache first (24h TTL)
  final cached = await dbService.getCachedRecommendations('daily_mix');
  if (cached != null && cached.isNotEmpty) {
    return cached.where((s) => s.isSingleSong).toList();
  }

  // 2. Fetch intelligent personalized discovery mix
  final mix = await recommender.getPersonalizedDiscoveryMix(limit: 15);

  // Save to 24h SQLite cache
  if (mix.isNotEmpty) {
    await dbService.setCachedRecommendations('daily_mix', mix, ttlHours: 24);
  }

  return mix;
});

// Provider rekomendasi berdasarkan kategori (dengan 12h SQLite Cache)
final recommendationProvider = FutureProvider.autoDispose<List<VideoItem>>((ref) async {
  final category = ref.watch(activeCategoryProvider);
  final ytService = YoutubeService();
  final dbService = DbService();
  final recommender = RecommendationService();
  final cacheKey = 'cat_${category.name}';

  // Check 12h cache
  final cached = await dbService.getCachedRecommendations(cacheKey);
  if (cached != null && cached.isNotEmpty) {
    return cached.where((s) => s.isSingleSong).toList();
  }

  List<VideoItem> results = [];

  switch (category) {
    case HomeCategory.all:
      final lastPlayed = await dbService.getLastPlayed();
      if (lastPlayed != null) {
        try {
          // Use Last.fm similarity graph for high-precision music recommendations
          results = await recommender.getSmartSongRadio(lastPlayed.toVideoItem(), limit: 15);
        } catch (_) {}
      }
      if (results.isEmpty) {
        final trending = await ytService.getTrendingVideos(maxResults: 15);
        results = trending.where((s) => s.isSingleSong).toList();
      }
      break;

    case HomeCategory.trending:
      final trending = await ytService.getTrendingVideos(maxResults: 15);
      results = trending.where((s) => s.isSingleSong).toList();
      break;

    case HomeCategory.music:
    case HomeCategory.gaming:
    case HomeCategory.news:
    case HomeCategory.live:
      final searched = await ytService.searchVideos(category.searchQuery, maxResults: 15);
      results = searched.where((s) => s.isSingleSong).toList();
      break;
  }

  if (results.isNotEmpty) {
    await dbService.setCachedRecommendations(cacheKey, results, ttlHours: 12);
  }

  return results;
});
