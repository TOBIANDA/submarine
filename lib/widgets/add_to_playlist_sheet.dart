// lib/widgets/add_to_playlist_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/video_item.dart';

import '../providers/playlist_provider.dart';
import '../services/db_service.dart';
import '../theme/app_theme.dart';

class AddToPlaylistSheet extends ConsumerWidget {
  final VideoItem video;

  const AddToPlaylistSheet({super.key, required this.video});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistAsync = ref.watch(playlistProvider);

    return Container(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Tambah ke Playlist',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          playlistAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: AppTheme.primary),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(20),
              child: Text('Error: $e',
                  style: const TextStyle(color: AppTheme.error)),
            ),
            data: (playlists) {
              if (playlists.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.playlist_add_rounded,
                          color: AppTheme.textMuted, size: 40),
                      SizedBox(height: 8),
                      Text('Belum ada playlist.\nBuat dulu di tab Library.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.textMuted)),
                    ],
                  ),
                );
              }
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: playlists.length,
                itemBuilder: (_, i) {
                  final playlist = playlists[i];
                  return ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: playlist.coverThumbnail != null
                          ? Image.network(playlist.coverThumbnail!,
                              width: 44, height: 44, fit: BoxFit.cover)
                          : Container(
                              width: 44,
                              height: 44,
                              color: AppTheme.surfaceVariant,
                              child: const Icon(Icons.queue_music_rounded,
                                  color: AppTheme.textMuted)),
                    ),
                    title: Text(playlist.title,
                        style: const TextStyle(color: AppTheme.textPrimary)),
                    subtitle: Text('${playlist.items.length} lagu',
                        style: const TextStyle(
                            color: AppTheme.textMuted, fontSize: 12)),
                    onTap: () async {
                      await DbService()
                          .addItemToPlaylist(playlist.id, video);
                      ref.read(playlistProvider.notifier).refresh();
                      if (context.mounted) {
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'Ditambahkan ke "${playlist.title}"'),
                            backgroundColor: AppTheme.primary,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        );
                      }
                    },
                  );
                },
              );
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  static void show(BuildContext context, VideoItem video) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => AddToPlaylistSheet(video: video),
    );
  }
}
