// lib/services/recommendation_service.dart
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/video_item.dart';
import 'db_service.dart';
import 'youtube_service.dart';

/// RecommendationService - Hybrid Recommendation Engine powered by Last.fm Graph API & On-Device Affinity Scoring
class RecommendationService {
  static RecommendationService? _instance;
  RecommendationService._();
  factory RecommendationService() => _instance ??= RecommendationService._();

  // Public Last.fm API Key pool (for similarity graph queries)
  static const List<String> _lastFmApiKeys = [
    '2c687e9112443a502f689e3a6c1e5c46',
    'b25b959554ed76058ac220b7b2e0a026',
    'c08a9010f3c5ea70d0b04a081a2f9b84',
  ];
  int _keyIndex = 0;
  String get _apiKey => _lastFmApiKeys[_keyIndex % _lastFmApiKeys.length];

  final YoutubeService _ytService = YoutubeService();
  final DbService _dbService = DbService();

  /// Clean song/artist title for precise Last.fm metadata lookup
  Map<String, String> _parseArtistAndTitle(String rawTitle, String channelTitle) {
    String cleanTitle = rawTitle
        .replaceAll(RegExp(r'\(.*?(official|audio|video|lyric|mv|hq|remaster).*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[.*?(official|audio|video|lyric|mv|hq|remaster).*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\|.*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'official\s+(audio|video|music\s+video)', caseSensitive: false), '')
        .trim();

    String artist = channelTitle.replaceAll(RegExp(r'\s*-\s*Topic', caseSensitive: false), '').trim();
    String track = cleanTitle;

    // If title contains "Artist - Song" or "Song - Artist"
    if (cleanTitle.contains(' - ')) {
      final parts = cleanTitle.split(' - ');
      if (parts.length >= 2) {
        artist = parts[0].trim();
        track = parts[1].trim();
      }
    } else if (cleanTitle.contains(' – ')) {
      final parts = cleanTitle.split(' – ');
      if (parts.length >= 2) {
        artist = parts[0].trim();
        track = parts[1].trim();
      }
    }

    return {'artist': artist, 'track': track};
  }

  /// 1. Query Last.fm Graph API for tracks similar to a given song
  Future<List<Map<String, dynamic>>> getSimilarTracksFromLastFm(String artist, String track, {int limit = 15}) async {
    try {
      final uri = Uri.parse(
        'https://ws.audioscrobbler.com/2.0/?method=track.getsimilar&artist=${Uri.encodeComponent(artist)}&track=${Uri.encodeComponent(track)}&api_key=$_apiKey&format=json&limit=$limit&autocorrect=1',
      );

      final resp = await http.get(uri).timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final simTracks = data['similartracks']?['track'];
        if (simTracks is List) {
          return simTracks.map<Map<String, dynamic>>((t) {
            final tName = t['name'] as String? ?? '';
            final tArtist = (t['artist'] is Map) ? (t['artist']['name'] as String? ?? '') : '';
            final match = double.tryParse(t['match']?.toString() ?? '0.5') ?? 0.5;
            return {
              'title': tName,
              'artist': tArtist,
              'matchScore': match,
              'query': '$tName $tArtist official audio',
            };
          }).toList();
        }
      }
    } catch (e) {
      debugPrint('[ML Recommender] Last.fm track.getsimilar error: $e');
      _keyIndex++;
    }

    // Fallback: Query artist similarity if track similarity yields no results
    return getSimilarArtistsFromLastFm(artist, limit: limit);
  }

  /// 2. Query Last.fm Graph API for artists similar to a given artist
  Future<List<Map<String, dynamic>>> getSimilarArtistsFromLastFm(String artist, {int limit = 10}) async {
    try {
      final uri = Uri.parse(
        'https://ws.audioscrobbler.com/2.0/?method=artist.getsimilar&artist=${Uri.encodeComponent(artist)}&api_key=$_apiKey&format=json&limit=$limit&autocorrect=1',
      );

      final resp = await http.get(uri).timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final simArtists = data['similarartists']?['artist'];
        if (simArtists is List) {
          return simArtists.map<Map<String, dynamic>>((a) {
            final aName = a['name'] as String? ?? '';
            final match = double.tryParse(a['match']?.toString() ?? '0.5') ?? 0.5;
            return {
              'title': 'Top Tracks',
              'artist': aName,
              'matchScore': match * 0.8,
              'query': '$aName popular official audio',
            };
          }).toList();
        }
      }
    } catch (e) {
      debugPrint('[ML Recommender] Last.fm artist.getsimilar error: $e');
    }
    return [];
  }

  /// 3. Compute On-Device User Affinity Scores & Filter Negative Signals (Skips)
  Future<Map<String, double>> computeUserAffinity() async {
    final history = await _dbService.getPlayHistory(limit: 50);
    final affinity = <String, double>{};
    final now = DateTime.now();

    for (final h in history) {
      final artist = h.channelTitle.replaceAll(RegExp(r'\s*-\s*Topic', caseSensitive: false), '').trim();
      final daysAgo = now.difference(h.playedAt).inHours / 24.0;
      final recencyDecay = exp(-daysAgo / 7.0); // 7-day half-life decay

      // Positive vs negative completion scoring
      double signal = 0.5;
      if (h.completionRate >= 0.70) {
        signal = 1.5; // Finished song -> strong positive
      } else if (h.completionRate < 0.25 && h.durationSeconds > 40) {
        signal = -1.5; // Skipped early -> strong negative penalty
      }

      final score = signal * recencyDecay;
      affinity[artist] = (affinity[artist] ?? 0.0) + score;
    }

    return affinity;
  }

  /// 4. Generate Smart Song Radio for the currently playing track
  Future<List<VideoItem>> getSmartSongRadio(VideoItem seedTrack, {int limit = 12}) async {
    final parsed = _parseArtistAndTitle(seedTrack.title, seedTrack.channelTitle);
    final artist = parsed['artist']!;
    final track = parsed['track']!;

    debugPrint('[ML Recommender] Generating Smart Radio for: $track by $artist');

    // 1. Fetch similarity graph candidates from Last.fm
    final graphCandidates = await getSimilarTracksFromLastFm(artist, track, limit: limit);

    // 2. Fetch on-device affinity scores
    final userAffinity = await computeUserAffinity();

    // 3. Rank candidates using Cosine Match + User Affinity
    graphCandidates.sort((a, b) {
      final matchA = (a['matchScore'] as double? ?? 0.5);
      final matchB = (b['matchScore'] as double? ?? 0.5);
      final affA = (userAffinity[a['artist']] ?? 0.0).clamp(-1.0, 2.0);
      final affB = (userAffinity[b['artist']] ?? 0.0).clamp(-1.0, 2.0);

      final totalScoreA = matchA * 0.7 + (affA * 0.15);
      final totalScoreB = matchB * 0.7 + (affB * 0.15);
      return totalScoreB.compareTo(totalScoreA);
    });

    final radioItems = <VideoItem>[];
    final seenIds = <String>{seedTrack.videoId};

    // 4. Resolve top ranked candidates to YouTube Videos
    for (final candidate in graphCandidates.take(6)) {
      try {
        final query = candidate['query'] as String;
        final res = await _ytService.searchVideos(query, maxResults: 2);
        for (final v in res) {
          if (v.isSingleSong && seenIds.add(v.videoId)) {
            radioItems.add(v);
            break;
          }
        }
      } catch (_) {}
    }

    // 5. If Last.fm was sparse, supplement with YouTube related videos
    if (radioItems.length < limit) {
      try {
        final related = await _ytService.getRelatedVideos(seedTrack, maxResults: limit - radioItems.length + 2);
        for (final v in related) {
          if (v.isSingleSong && seenIds.add(v.videoId)) {
            radioItems.add(v);
          }
        }
      } catch (_) {}
    }

    return radioItems;
  }

  /// 5. Generate Personalized AI & Graph Discovery Playlist
  Future<List<VideoItem>> getPersonalizedDiscoveryMix({int limit = 15}) async {
    final history = await _dbService.getPlayHistory(limit: 30);
    if (history.isEmpty) {
      return _ytService.getTrendingVideos(maxResults: limit);
    }

    final topCompleted = history.where((h) => h.completionRate >= 0.6).toList();
    final seed = topCompleted.isNotEmpty ? topCompleted[Random().nextInt(topCompleted.length)] : history.first;

    final parsed = _parseArtistAndTitle(seed.title, seed.channelTitle);
    return getSmartSongRadio(seed.toVideoItem(), limit: limit);
  }
}
