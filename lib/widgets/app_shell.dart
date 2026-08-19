// lib/widgets/app_shell.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:miniplayer/miniplayer.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
          navigationShell,

          // Mini Player overlay above content
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

// ──────────────────────────────────────────────
// Music Mini Player (Spotify Style)
// ──────────────────────────────────────────────
class _MusicMiniPlayer extends StatelessWidget {
  final PlayerService player;

  const _MusicMiniPlayer({required this.player});

  @override
  Widget build(BuildContext context) {
    final video = player.currentVideo;
    if (video == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            context.push('/player', extra: video);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                // Album Art
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: video.thumbnailUrl,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: AppTheme.surfaceVariant),
                    errorWidget: (_, __, ___) => const Icon(Icons.music_note, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),

                // Title & Artist
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        video.channelTitle,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // Play/Pause Button
                IconButton(
                  icon: Icon(
                    player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                  onPressed: () {
                    player.togglePlay();
                  },
                ),

                // Next Button
                IconButton(
                  icon: const Icon(
                    Icons.skip_next_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                  onPressed: () {
                    player.playNext();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Bottom Navigation Bar (4 Tabs: Beranda, Cari, Library, Profil)
// ──────────────────────────────────────────────
class _BottomNavBar extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const _BottomNavBar({required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.background,
        border: Border(top: BorderSide(color: AppTheme.divider, width: 0.5)),
      ),
      child: NavigationBar(
        backgroundColor: AppTheme.background,
        indicatorColor: const Color(0xFF28244C),
        selectedIndex: navigationShell.currentIndex,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 64,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded, color: AppTheme.primaryLight),
            label: 'Beranda',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_rounded),
            selectedIcon: Icon(Icons.search_rounded, color: AppTheme.primaryLight),
            label: 'Cari',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music_rounded, color: AppTheme.primaryLight),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded, color: AppTheme.primaryLight),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}
