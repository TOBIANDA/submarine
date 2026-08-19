// lib/widgets/video_list_tile.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/video_item.dart';
import '../theme/app_theme.dart';
import '../providers/download_provider.dart';

class VideoListTile extends ConsumerWidget {
  final VideoItem video;
  final VoidCallback? onTap;
  final VoidCallback? onPlayNow;
  final VoidCallback? onAddToQueue;
  final VoidCallback? onAddToPlaylist;
  final Widget? leading;
  final bool showDragHandle;
  final bool isPlaying;

  const VideoListTile({
    super.key,
    required this.video,
    this.onTap,
    this.onPlayNow,
    this.onAddToQueue,
    this.onAddToPlaylist,
    this.leading,
    this.showDragHandle = false,
    this.isPlaying = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDownloadedAsync = ref.watch(isDownloadedProvider(video.videoId));
    final isDownloaded = isDownloadedAsync.value ?? false;

    final activeDownloads = ref.watch(activeDownloadsProvider);
    final activeDownload = activeDownloads[video.videoId];
    final isDownloading = activeDownload != null;
    final downloadProgress = activeDownload?.progress ?? 0.0;
    final isWaiting = activeDownload?.isWaiting ?? false;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Drag handle or leading widget
            if (showDragHandle)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(Icons.drag_handle_rounded,
                    color: AppTheme.textMuted, size: 20),
              )
            else if (leading != null)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: leading,
              ),

            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  CachedNetworkImage(
                    imageUrl: video.thumbnailHighRes,
                    width: 72,
                    height: 48,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      width: 72,
                      height: 48,
                      color: AppTheme.surfaceVariant,
                      child: const Icon(Icons.music_video_rounded,
                          color: AppTheme.textMuted, size: 20),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      width: 72,
                      height: 48,
                      color: AppTheme.surfaceVariant,
                      child: const Icon(Icons.broken_image_rounded,
                          color: AppTheme.textMuted, size: 20),
                    ),
                  ),
                  if (isPlaying)
                    Container(
                      width: 72,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.7),
                      ),
                      child: const Icon(Icons.equalizer_rounded,
                          color: Colors.white, size: 20),
                    ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // Title + Channel
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isPlaying ? AppTheme.primary : AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          video.channelTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppTheme.textMuted, fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (isDownloading)
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: isWaiting
                              ? const Icon(Icons.access_time_rounded,
                                  color: AppTheme.textMuted, size: 12)
                              : CircularProgressIndicator(
                                  value: downloadProgress,
                                  strokeWidth: 2,
                                  color: AppTheme.primary,
                                ),
                        )
                      else if (isDownloaded)
                        const Icon(Icons.check_circle_rounded,
                            color: Colors.green, size: 14),
                      if (isDownloading || isDownloaded)
                        const SizedBox(width: 4),
                      Text(
                        video.formattedDuration,
                        style: const TextStyle(
                            color: AppTheme.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // More options button
            if (onPlayNow != null || onAddToQueue != null || onAddToPlaylist != null || !isDownloaded)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded,
                    color: AppTheme.textMuted, size: 20),
                color: AppTheme.surfaceVariant,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                onSelected: (value) {
                  switch (value) {
                    case 'play_now':
                      onPlayNow?.call();
                      break;
                    case 'add_queue':
                      onAddToQueue?.call();
                      break;
                    case 'add_playlist':
                      onAddToPlaylist?.call();
                      break;
                    case 'download':
                      ref.read(activeDownloadsProvider.notifier).startDownload(video);
                      break;
                  }
                },
                itemBuilder: (_) => [
                  if (!isDownloaded && !isDownloading)
                    const PopupMenuItem(
                      value: 'download',
                      child: Row(
                        children: [
                          Icon(Icons.download_rounded,
                              color: AppTheme.primary, size: 18),
                          SizedBox(width: 10),
                          Text('Unduh Offline',
                              style: TextStyle(color: AppTheme.textPrimary)),
                        ],
                      ),
                    ),
                  if (onPlayNow != null)
                    const PopupMenuItem(
                      value: 'play_now',
                      child: Row(
                        children: [
                          Icon(Icons.play_arrow_rounded,
                              color: AppTheme.primary, size: 18),
                          SizedBox(width: 10),
                          Text('Putar Sekarang',
                              style: TextStyle(color: AppTheme.textPrimary)),
                        ],
                      ),
                    ),
                  if (onAddToQueue != null)
                    const PopupMenuItem(
                      value: 'add_queue',
                      child: Row(
                        children: [
                          Icon(Icons.queue_music_rounded,
                              color: AppTheme.textSecondary, size: 18),
                          SizedBox(width: 10),
                          Text('Putar Selanjutnya',
                              style: TextStyle(color: AppTheme.textPrimary)),
                        ],
                      ),
                    ),
                  if (onAddToPlaylist != null)
                    const PopupMenuItem(
                      value: 'add_playlist',
                      child: Row(
                        children: [
                          Icon(Icons.playlist_add_rounded,
                              color: AppTheme.textSecondary, size: 18),
                          SizedBox(width: 10),
                          Text('Tambah ke Playlist',
                              style: TextStyle(color: AppTheme.textPrimary)),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
