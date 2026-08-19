// lib/widgets/app_shell.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../providers/player_provider.dart';
import '../services/player_service.dart';
import '../theme/app_theme.dart';

class AppShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerServiceProvider);
    final currentVideo = player.currentVideo;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          // Background YouTube Player Widget (keeps webview active & playing audio)
          Offstage(
            offstage: true,
            child: SizedBox(
              width: 100,
              height: 100,
              child: YoutubePlayer(
                controller: player.youtubeController,
                showVideoProgressIndicator: false,
              ),
            ),
          ),

          navigationShell,

          // Mini Player overlay above content (Dismissible with horizontal swipe)
          if (currentVideo != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: _MusicMiniPlayer(player: player),
            ),
        ],
      ),
      bottomNavigationBar: _BottomNavBar(navigationShell: navigationShell),
    );
  }
}

// ─────────────────────────────────────────────
// Music Mini Player (Spotify Style with Swipe-to-Dismiss)
// ─────────────────────────────────────────────
class _MusicMiniPlayer extends StatelessWidget {
  final PlayerService player;

  const _MusicMiniPlayer({required this.player});

  @override
  Widget build(BuildContext context) {
    final video = player.currentVideo;
    if (video == null) return const SizedBox.shrink();

    return Dismissible(
      key: ValueKey('mini_player_${video.videoId}'),
      direction: DismissDirection.horizontal,
      onDismissed: (_) {
        player.stop();
      },
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.3),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.centerLeft,
        child: const Row(
          children: [
            Icon(Icons.close_rounded, color: Colors.white, size: 24),
            SizedBox(width: 8),
            Text('Tutup Pemutar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.3),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.centerRight,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Tutup Pemutar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
            SizedBox(width: 8),
            Icon(Icons.close_rounded, color: Colors.white, size: 24),
          ],
        ),
      ),
      child: GestureDetector(
        onTap: () {
          context.push('/player', extra: video);
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.surface.withOpacity(0.96),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withOpacity(0.12),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: video.thumbnailUrl,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    width: 44,
                    height: 44,
                    color: AppTheme.surfaceVariant,
                    child: const Icon(Icons.music_note, color: AppTheme.textMuted, size: 22),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Title & Artist
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      video.channelTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              // Controls
              if (player.isLoadingAudio)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primary,
                    ),
                  ),
                )
              else
                IconButton(
                  icon: Icon(
                    player.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: AppTheme.primary,
                    size: 28,
                  ),
                  onPressed: () => player.togglePlay(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),

              IconButton(
                icon: const Icon(
                  Icons.skip_next_rounded,
                  color: AppTheme.textSecondary,
                  size: 24,
                ),
                onPressed: player.hasNext ? () => player.playNext() : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),

              // Close / Dismiss button
              IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  color: AppTheme.textMuted,
                  size: 20,
                ),
                onPressed: () => player.stop(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: 'Tutup',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Bottom Nav Bar
// ─────────────────────────────────────────────
class _BottomNavBar extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const _BottomNavBar({required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          top: BorderSide(
            color: Colors.white.withOpacity(0.08),
            width: 0.5,
          ),
        ),
      ),
      child: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        backgroundColor: Colors.transparent,
        indicatorColor: AppTheme.primary.withOpacity(0.18),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded, color: AppTheme.primary),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search_rounded, color: AppTheme.primary),
            label: 'Cari',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music_rounded, color: AppTheme.primary),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download_done_rounded, color: AppTheme.primary),
            label: 'Download',
          ),
        ],
      ),
    );
  }
}
