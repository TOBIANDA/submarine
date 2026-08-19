// lib/router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'widgets/app_shell.dart';
import 'screens/home/home_screen.dart';
import 'screens/search/search_screen.dart';
import 'screens/library/library_screen.dart';
import 'screens/library/playlist_detail_screen.dart';
import 'screens/library/ai_create_playlist_screen.dart';
import 'screens/library/ai_edit_playlist_screen.dart';
import 'screens/player/full_player_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/channel/channel_screen.dart';
import 'models/video_item.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final goRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/home',
  routes: [
    // ── Full Player (modal, above shell) ─────────────────
    GoRoute(
      path: '/player',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (_, state) => CustomTransitionPage(
        key: state.pageKey,
        child: FullPlayerScreen(video: state.extra as VideoItem),
        transitionsBuilder: (_, animation, __, child) => SlideTransition(
          position: animation.drive(
            Tween(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).chain(CurveTween(curve: Curves.easeOutCubic)),
          ),
          child: child,
        ),
      ),
    ),

    // ── Channel Detail Screen (above shell) ──────────────
    GoRoute(
      path: '/channel/:id',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final channelId = state.pathParameters['id']!;
        final initialTitle = state.extra as String?;
        return ChannelScreen(
          channelId: channelId,
          initialTitle: initialTitle,
        );
      },
    ),

    // ── Shell (bottom nav + mini player) ─────────────────
    StatefulShellRoute.indexedStack(
      builder: (_, __, shell) => AppShell(navigationShell: shell),
      branches: [
        // ── Branch 0: Home ────────────────────────────────
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              builder: (_, __) => const HomeScreen(),
            ),
          ],
        ),

        // ── Branch 1: Search ──────────────────────────────
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/search',
              builder: (_, __) => const SearchScreen(),
            ),
          ],
        ),

        // ── Branch 2: Library ─────────────────────────────
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/library',
              builder: (_, __) => const LibraryScreen(),
              routes: [
                GoRoute(
                  path: 'ai-create',
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (_, __) => const AiCreatePlaylistScreen(),
                ),
                GoRoute(
                  path: ':id',
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (_, state) => PlaylistDetailScreen(
                    playlistId: state.pathParameters['id']!,
                  ),
                  routes: [
                    GoRoute(
                      path: 'ai-edit',
                      parentNavigatorKey: _rootNavigatorKey,
                      builder: (_, state) => AiEditPlaylistScreen(
                        playlistId: state.pathParameters['id']!,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),

        // ── Branch 3: Profile ─────────────────────────────
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/profile',
              builder: (_, __) => const ProfileScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);
