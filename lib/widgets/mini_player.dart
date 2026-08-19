// lib/widgets/mini_player.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:marquee/marquee.dart';

import '../providers/player_provider.dart';
import '../theme/app_theme.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final video = ref.watch(currentVideoProvider);
    final isPlaying = ref.watch(isPlayingProvider);
    // Gunakan watch agar hasPrevious/hasNext reactive
    final player = ref.watch(playerServiceProvider);

    if (video == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => context.push('/player'),
      child: Container(
        height: 70,
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          border: Border(
            top: BorderSide(color: AppTheme.divider, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(0),
              child: CachedNetworkImage(
                imageUrl: video.thumbnailHighRes,
                width: 70,
                height: 70,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                    color: AppTheme.surfaceVariant,
                    child: const Icon(Icons.music_video_rounded,
                        color: AppTheme.textMuted)),
                errorWidget: (_, __, ___) => Container(
                    color: AppTheme.surfaceVariant,
                    child: const Icon(Icons.music_video_rounded,
                        color: AppTheme.textMuted)),
              ),
            ),

            const SizedBox(width: 12),

            // Title + Channel (scrolling if long)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 20,
                    child: video.title.length > 30
                        ? Marquee(
                            text: video.title,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            scrollAxis: Axis.horizontal,
                            blankSpace: 40,
                            velocity: 30,
                            pauseAfterRound: const Duration(seconds: 2),
                          )
                        : Text(
                            video.title,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    video.channelTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),

            // Controls
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.skip_previous_rounded,
                    color: player.hasPrevious
                        ? AppTheme.textSecondary
                        : AppTheme.textMuted,
                  ),
                  iconSize: 22,
                  onPressed:
                      player.hasPrevious ? () => player.playPrevious() : null,
                  tooltip: 'Sebelumnya',
                ),
                GestureDetector(
                  onTap: () => player.togglePlay(),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: AppTheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next_rounded),
                  color: AppTheme.textSecondary,
                  iconSize: 22,
                  onPressed: () => player.playNext(),
                  tooltip: 'Berikutnya',
                ),
                const SizedBox(width: 4),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
