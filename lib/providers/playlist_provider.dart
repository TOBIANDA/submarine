// lib/providers/playlist_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/playlist.dart';
import '../services/db_service.dart';

class PlaylistNotifier extends AsyncNotifier<List<Playlist>> {
  @override
  Future<List<Playlist>> build() async {
    return DbService().getAllPlaylists();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => DbService().getAllPlaylists());
  }

  Future<void> addPlaylist(Playlist playlist) async {
    await DbService().insertPlaylist(playlist);
    await refresh();
  }

  Future<void> deletePlaylist(String id) async {
    await DbService().deletePlaylist(id);
    await refresh();
  }

  Future<void> renamePlaylist(String id, String title) async {
    await DbService().updatePlaylistTitle(id, title);
    await refresh();
  }
}

final playlistProvider =
    AsyncNotifierProvider<PlaylistNotifier, List<Playlist>>(
        PlaylistNotifier.new);

/// Provider for a single playlist by ID (auto-refreshes with playlistProvider)
final singlePlaylistProvider =
    FutureProvider.family<Playlist?, String>((ref, id) async {
  // Watch the list so this re-evaluates when playlists change
  ref.watch(playlistProvider);
  return DbService().getPlaylist(id);
});
