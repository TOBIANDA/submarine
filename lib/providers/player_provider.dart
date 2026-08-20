// lib/providers/player_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/player_service.dart';
import '../services/audio_handler.dart';
import '../models/video_item.dart';
import 'history_provider.dart';

// Expose the audio handler so it can be read globally
final audioHandlerProvider = Provider<BackgroundAudioHandler>((ref) {
  // This will be overridden in main.dart after AudioService.init()
  throw UnimplementedError('audioHandlerProvider must be overridden');
});

/// Provider exposing the PlayerService singleton as a ChangeNotifier
final playerServiceProvider = ChangeNotifierProvider<PlayerService>((ref) {
  final handler = ref.read(audioHandlerProvider);
  final service = PlayerService();
  service.init(handler);
  service.onHistoryUpdated = () {
    ref.invalidate(historyProvider);
    ref.invalidate(lastPlayedProvider);
  };
  return service;
});

/// Convenience computed providers
final currentVideoProvider = Provider<VideoItem?>((ref) {
  return ref.watch(playerServiceProvider).currentVideo;
});

final isPlayingProvider = Provider<bool>((ref) {
  return ref.watch(playerServiceProvider).isPlaying;
});


final repeatModeProvider = Provider<RepeatMode>((ref) {
  return ref.watch(playerServiceProvider).repeatMode;
});

final isShuffledProvider = Provider<bool>((ref) {
  return ref.watch(playerServiceProvider).isShuffled;
});

final queueProvider = Provider<List<VideoItem>>((ref) {
  return ref.watch(playerServiceProvider).queue;
});

final isLoadingAudioProvider = Provider<bool>((ref) {
  return ref.watch(playerServiceProvider).isLoadingAudio;
});

