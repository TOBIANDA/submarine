// lib/widgets/app_shell.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../providers/player_provider.dart';
import '../services/player_service.dart';
import '../services/permission_service.dart';
import '../theme/app_theme.dart';

class AppShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({super.key, required this.navigationShell});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        PermissionService.requestBatteryAndNotificationPermissions(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerServiceProvider);
    final currentVideo = player.currentVideo;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          widget.navigationShell,

          // Mini Player overlay above content (Dismissible with horizontal swipe or close button)
          if (currentVideo != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: _MusicMiniPlayer(player: player),
            ),
        ],
      ),
      bottomNavigationBar: _BottomNavBar(navigationShell: widget.navigationShell),
    );
  }
}

// ─────────────────────────────────────────────
// Music Mini Player (Spotify Style with Swipe-to-Dismiss & Close Button)
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
          color: Colors.red.withValues(alpha: 0.3),
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
          color: Colors.red.withValues(alpha: 0.3),
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
        onTap: () => context.push('/player'),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2E).withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.primary.withValues(alpha: 0.25),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // Album Art Thumbnail
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
                        color: AppTheme.cardColor,
                        child: const Icon(Icons.music_note, color: Colors.white54),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Song Title & Artist
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          video.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          video.channelTitle,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // Previous Button
                  IconButton(
                    icon: Icon(
                      Icons.skip_previous_rounded,
                      color: player.hasPrevious ? Colors.white : Colors.white24,
                      size: 22,
                    ),
                    onPressed: player.hasPrevious ? player.playPrevious : null,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),

                  // Play / Pause Button
                  if (player.isLoadingAudio && !player.isPlaying)
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: Padding(
                        padding: EdgeInsets.all(4),
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                      ),
                    )
                  else
                    IconButton(
                      icon: Icon(
                        player.isPlaying
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_fill_rounded,
                        color: AppTheme.primary,
                        size: 32,
                      ),
                      onPressed: player.togglePlay,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),

                  // Next Button
                  IconButton(
                    icon: Icon(
                      Icons.skip_next_rounded,
                      color: player.hasNext ? Colors.white : Colors.white24,
                      size: 22,
                    ),
                    onPressed: player.hasNext ? player.playNext : null,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),

                  // Close Button (Tutup Pemutar)
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white54,
                      size: 20,
                    ),
                    onPressed: () => player.stop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    tooltip: 'Tutup pemutar',
                  ),
                ],
              ),

              // Progress Bar at bottom of miniplayer
              const SizedBox(height: 6),
              StreamBuilder<Duration>(
                stream: player.positionStream,
                builder: (context, snapshot) {
                  final position = snapshot.data ?? Duration.zero;
                  final duration = player.duration ?? Duration.zero;
                  final progress = duration.inMilliseconds > 0
                      ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
                      : 0.0;

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                      minHeight: 2,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Bottom Navigation Bar
// ─────────────────────────────────────────────
class _BottomNavBar extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const _BottomNavBar({required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: navigationShell.currentIndex,
      onDestinationSelected: (index) => navigationShell.goBranch(
        index,
        initialLocation: index == navigationShell.currentIndex,
      ),
      backgroundColor: AppTheme.surface,
      indicatorColor: AppTheme.primary.withValues(alpha: 0.15),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded, color: AppTheme.primary),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.search_outlined),
          selectedIcon: Icon(Icons.search_rounded, color: AppTheme.primary),
          label: 'Search',
        ),
        NavigationDestination(
          icon: Icon(Icons.library_music_outlined),
          selectedIcon: Icon(Icons.library_music_rounded, color: AppTheme.primary),
          label: 'Library',
        ),
        NavigationDestination(
          icon: Icon(Icons.download_outlined),
          selectedIcon: Icon(Icons.download_rounded, color: AppTheme.primary),
          label: 'Downloads',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person_rounded, color: AppTheme.primary),
          label: 'Profile',
        ),
      ],
    );
  }
}
