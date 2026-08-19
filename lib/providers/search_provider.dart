// lib/providers/search_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/video_item.dart';
import '../services/youtube_service.dart';

class SearchState {
  final List<VideoItem> results;
  final bool isLoading;
  final String? error;
  final String query;

  const SearchState({
    this.results = const [],
    this.isLoading = false,
    this.error,
    this.query = '',
  });

  SearchState copyWith({
    List<VideoItem>? results,
    bool? isLoading,
    String? error,
    String? query,
  }) =>
      SearchState(
        results: results ?? this.results,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        query: query ?? this.query,
      );
}

class SearchNotifier extends Notifier<SearchState> {
  @override
  SearchState build() => const SearchState();

  Future<void> search(String query) async {
    if (query.trim().isEmpty) {
      state = const SearchState();
      return;
    }

    state = state.copyWith(isLoading: true, error: null, query: query);

    try {
      final results = await YoutubeService().searchVideos(query.trim());
      state = state.copyWith(results: results, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Pencarian gagal: ${e.toString()}',
      );
    }
  }

  void clear() {
    state = const SearchState();
  }
}

final searchProvider =
    NotifierProvider<SearchNotifier, SearchState>(SearchNotifier.new);
