// lib/screens/downloads/downloads_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/download_provider.dart';
import '../../providers/player_provider.dart';
import '../../services/download_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/video_list_tile.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadsAsync = ref.watch(downloadedTracksProvider);
    final activeDownloads = ref.watch(activeDownloadsProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Offline Downloads'),
        backgroundColor: AppTheme.background,
      ),
      body: CustomScrollView(
        slivers: [
          // Bagian: Sedang Diunduh
          if (activeDownloads.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Sedang Diunduh',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final activeDownloadList = activeDownloads.values.toList();
                  final item = activeDownloadList[index];

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        // Thumbnail
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            item.video.thumbnailUrl,
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Title & Progress Bar
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.video.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (item.isWaiting)
                                const Row(
                                  children: [
                                    Icon(Icons.access_time_rounded, size: 12, color: AppTheme.textMuted),
                                    SizedBox(width: 4),
                                    Text(
                                      'Mengantre...',
                                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                                    ),
                                  ],
                                )
                              else
                                Row(
                                  children: [
                                    Expanded(
                                      child: LinearProgressIndicator(
                                        value: item.progress,
                                        backgroundColor: AppTheme.surfaceVariant,
                                        color: AppTheme.primary,
                                        minHeight: 4,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${(item.progress * 100).toStringAsFixed(0)}%',
                                      style: const TextStyle(
                                          color: AppTheme.textSecondary, fontSize: 12),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                          onPressed: () {
                            ref.read(activeDownloadsProvider.notifier).cancelDownload(item.video.videoId);
                          },
                          tooltip: 'Batalkan',
                        ),
                      ],
                    ),
                  );
                },
                childCount: activeDownloads.length,
              ),
            ),
            const SliverToBoxAdapter(
              child: Divider(color: AppTheme.surfaceVariant, height: 32),
            ),
          ],

          // Bagian: Selesai Diunduh
          downloadsAsync.when(
            data: (tracks) {
              if (tracks.isEmpty && activeDownloads.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.download_done_rounded,
                            size: 64, color: AppTheme.surfaceVariant),
                        SizedBox(height: 16),
                        Text(
                          'Belum ada lagu yang diunduh.',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (tracks.isEmpty) {
                return const SliverToBoxAdapter(child: SizedBox.shrink());
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index == 0) {
                      return const Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Text(
                          'Selesai Diunduh',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }

                    final track = tracks[index - 1]; // -1 because index 0 is the header
                    final videoItem = track.toVideoItem();

                    return Dismissible(
                      key: Key(track.videoId),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Colors.red.withValues(alpha: 0.8),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: const Icon(Icons.delete_rounded, color: Colors.white),
                      ),
                      confirmDismiss: (_) async {
                        return await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: AppTheme.surface,
                            title: const Text('Hapus Unduhan?',
                                style: TextStyle(color: AppTheme.textPrimary)),
                            content: const Text(
                                'Lagu ini akan dihapus dari memori HP Anda.',
                                style: TextStyle(color: AppTheme.textSecondary)),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Batal',
                                    style: TextStyle(color: AppTheme.textMuted)),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Hapus',
                                    style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                      },
                      onDismissed: (_) async {
                        await DownloadService().deleteDownload(track.videoId);
                        ref.invalidate(downloadedTracksProvider);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Unduhan dihapus.')),
                          );
                        }
                      },
                      child: VideoListTile(
                        video: videoItem,
                        onPlayNow: () {
                          final playerService = ref.read(playerServiceProvider);
                          playerService.playSingle(videoItem);
                        },
                        onAddToQueue: () {
                          final playerService = ref.read(playerServiceProvider);
                          playerService.addToQueue(videoItem);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Ditambahkan ke antrean')),
                          );
                        },
                      ),
                    );
                  },
                  childCount: tracks.length + 1, // +1 for the header
                ),
              );
            },
            loading: () => const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: AppTheme.primary),
              ),
            ),
            error: (err, stack) => SliverFillRemaining(
              child: Center(
                child: Text(
                  'Terjadi kesalahan: $err',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: SizedBox(height: 100), // padding bawah
          ),
        ],
      ),
    );
  }
}
