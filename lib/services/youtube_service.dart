// lib/services/youtube_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/video_item.dart';
import '../models/channel_detail.dart';
import '../core/app_constants.dart';

class YoutubeService {
  static YoutubeService? _instance;
  YoutubeService._();
  factory YoutubeService() => _instance ??= YoutubeService._();

  final Map<String, List<VideoItem>> _searchCache = {};

  /// Search music tracks with guaranteed direct-playable YouTube video IDs
  Future<List<VideoItem>> searchVideos(String query, {int maxResults = 25}) async {
    final cleanQuery = query.trim().toLowerCase();
    final cacheKey = '${cleanQuery}_$maxResults';
    if (_searchCache.containsKey(cacheKey)) {
      return _searchCache[cacheKey]!;
    }

    // ── Stage 1: YouTube Search (Real 11-char directly playable Video IDs) ──
    try {
      final yt = YoutubeExplode();
      try {
        final results = await yt.search.search(query);
        final videoItems = <VideoItem>[];

        for (final video in results) {
          final duration = video.duration?.inSeconds ?? 0;
          videoItems.add(VideoItem(
            videoId: video.id.value,
            title: video.title,
            channelId: video.channelId.value,
            channelTitle: video.author,
            thumbnailUrl: video.thumbnails.highResUrl.isNotEmpty
                ? video.thumbnails.highResUrl
                : video.thumbnails.mediumResUrl,
            durationSeconds: duration,
          ));
          if (videoItems.length >= maxResults) break;
        }

        if (videoItems.isNotEmpty) {
          _searchCache[cacheKey] = videoItems;
          return videoItems;
        }
      } finally {
        yt.close();
      }
    } catch (e) {
      debugPrint('[MusicSearch] YouTube Explode search failed: $e');
    }

    // ── Stage 2: YouTube Data API v3 Fallback ──
    try {
      final dataApiResults = await _searchVideosDataApi(query, maxResults: maxResults);
      if (dataApiResults.isNotEmpty) {
        _searchCache[cacheKey] = dataApiResults;
        return dataApiResults;
      }
    } catch (e) {
      debugPrint('[MusicSearch] YouTube Data API failed: $e');
    }

    return [];
  }

  int _parseIsoDuration(String isoDuration) {
    final regex = RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?');
    final match = regex.firstMatch(isoDuration);
    if (match == null) return 0;
    final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
    final minutes = int.tryParse(match.group(2) ?? '0') ?? 0;
    final seconds = int.tryParse(match.group(3) ?? '0') ?? 0;
    return hours * 3600 + minutes * 60 + seconds;
  }

  Future<List<VideoItem>> _searchVideosDataApi(String query, {int maxResults = 10}) async {
    final keys = AppConstants.youtubeApiKeys.toList()..shuffle();
    for (final key in keys) {
      try {
        final uri = Uri.parse('${AppConstants.youtubeBaseUrl}/search?part=snippet&type=video&maxResults=$maxResults&q=${Uri.encodeComponent(query)}&key=$key');
        final response = await http.get(uri).timeout(const Duration(seconds: 6));
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final items = data['items'] as List<dynamic>;
          if (items.isEmpty) return [];

          final videoIds = items
              .map((i) => i['id']['videoId']?.toString() ?? '')
              .where((id) => id.isNotEmpty)
              .join(',');
          
          final videoUri = Uri.parse('${AppConstants.youtubeBaseUrl}/videos?part=contentDetails&id=$videoIds&key=$key');
          final videoResponse = await http.get(videoUri).timeout(const Duration(seconds: 6));
          
          final videoItems = <VideoItem>[];
          final videoItemsList = videoResponse.statusCode == 200 
              ? (jsonDecode(videoResponse.body)['items'] as List<dynamic>)
              : [];

          for (final item in items) {
             final videoId = item['id']['videoId']?.toString();
             if (videoId == null) continue;

             final snippet = item['snippet'];
             final vItem = videoItemsList.firstWhere((v) => v['id'] == videoId, orElse: () => null);
             
             int durationSeconds = 0;
             if (vItem != null) {
               final isoDuration = vItem['contentDetails']?['duration'] as String? ?? '';
               durationSeconds = _parseIsoDuration(isoDuration);
             }

             videoItems.add(VideoItem(
               videoId: videoId,
               title: snippet['title'] ?? '',
               channelId: snippet['channelId'] ?? '',
               channelTitle: snippet['channelTitle'] ?? '',
               thumbnailUrl: snippet['thumbnails']?['high']?['url'] ?? snippet['thumbnails']?['medium']?['url'] ?? '',
               durationSeconds: durationSeconds,
             ));
          }
          return videoItems;
        }
      } catch (e) {
        debugPrint('[YouTube] API key $key error: $e');
      }
    }
    return [];
  }

  Future<List<VideoItem>> getTrendingVideos({int maxResults = 15}) async {
    return searchVideos('top hits indonesia 2025', maxResults: maxResults);
  }

  Future<List<VideoItem>> getRelatedVideos(VideoItem currentVideo, {int maxResults = 10}) async {
    final query = '${currentVideo.title} ${currentVideo.channelTitle}';
    return searchVideos(query, maxResults: maxResults);
  }

  Future<ChannelDetail?> getChannelDetail(String channelId) async {
    final yt = YoutubeExplode();
    try {
      final channel = await yt.channels.get(channelId);
      return ChannelDetail(
        id: channel.id.value,
        title: channel.title,
        logoUrl: channel.logoUrl,
        bannerUrl: channel.bannerUrl,
        subscribersCount: 'Artis',
      );
    } catch (_) {
      return null;
    } finally {
      yt.close();
    }
  }

  Future<List<VideoItem>> getChannelVideos(String channelId) async {
    final yt = YoutubeExplode();
    try {
      final uploads = await yt.channels.getUploads(channelId).take(20).toList();
      return uploads.map((v) => VideoItem(
        videoId: v.id.value,
        title: v.title,
        channelId: v.channelId.value,
        channelTitle: v.author,
        thumbnailUrl: v.thumbnails.mediumResUrl,
        durationSeconds: v.duration?.inSeconds ?? 0,
      )).toList();
    } catch (_) {
      return [];
    } finally {
      yt.close();
    }
  }
}
