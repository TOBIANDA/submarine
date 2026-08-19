// lib/screens/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../providers/recommendation_provider.dart';
import '../../providers/player_provider.dart';
import '../../models/video_item.dart';
import '../../theme/app_theme.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedCategoryIndex = 0;
  final List<String> _categories = ['All', 'Music', 'Podcasts'];

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'good morning,';
    if (hour < 17) return 'good afternoon,';
    return 'good evening,';
  }

  @override
  Widget build(BuildContext context) {
    final recommendationAsync = ref.watch(recommendationProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(recommendationProvider);
          },
          color: AppTheme.primaryLight,
          backgroundColor: AppTheme.surfaceVariant,
          child: CustomScrollView(
            slivers: [
              // ── Header (Greeting + Title + Icons) ──────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getGreeting(),
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Submarine',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.search_rounded, color: Colors.white, size: 26),
                            onPressed: () => context.go('/search'),
                          ),
                          GestureDetector(
                            onTap: () => context.go('/profile'),
                            child: const CircleAvatar(
                              radius: 18,
                              backgroundColor: Color(0xFF28244C),
                              child: Icon(Icons.person, color: AppTheme.primaryLight, size: 20),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // ── Category Pills (All, Music, Podcasts) ───────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: List.generate(_categories.length, (index) {
                      final isSelected = _selectedCategoryIndex == index;
                      return Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedCategoryIndex = index;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF6C4CE0) : const Color(0xFF1E1E2E),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _categories[index],
                              style: TextStyle(
                                color: isSelected ? Colors.white : AppTheme.textSecondary,
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),

              // ── AI Playlist Quick Action Card ───────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => context.push('/library/ai-create'),
                        child: Container(
                          height: 56,
                          padding: const EdgeInsets.only(right: 18),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E2E),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Color(0xFF25D9A0), Color(0xFF1FBF9C)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.horizontal(left: Radius.circular(12)),
                                ),
                                child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 24),
                              ),
                              const SizedBox(width: 14),
                              const Text(
                                'AI Playlist',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Section: Top Picks for You ───────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                  child: const Text(
                    'Top Picks for You',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              // ── Horizontal Cards List ────────────────────────────
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 220,
                  child: recommendationAsync.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(color: AppTheme.primaryLight),
                    ),
                    error: (e, _) => Center(
                      child: Text('Gagal memuat: $e', style: const TextStyle(color: AppTheme.textSecondary)),
                    ),
                    data: (videos) {
                      if (videos.isEmpty) {
                        return const Center(
                          child: Text('Tidak ada lagu', style: TextStyle(color: AppTheme.textSecondary)),
                        );
                      }
                      return ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: videos.length,
                        itemBuilder: (context, index) {
                          final video = videos[index];
                          return _SquareMusicCard(
                            video: video,
                            onTap: () {
                              ref.read(playerServiceProvider).playSingle(video);
                              context.push('/player', extra: video);
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ),

              // ── Section: Lagu Populer Lainnya ────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                  child: const Text(
                    'Lagu Populer',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              // ── Vertical Tracks List ─────────────────────────────
              recommendationAsync.when(
                loading: () => const SliverToBoxAdapter(child: SizedBox(height: 100)),
                error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
                data: (videos) {
                  return SliverPadding(
                    padding: const EdgeInsets.only(bottom: 90),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final video = videos[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: video.thumbnailUrl,
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(color: const Color(0xFF1E1E2E)),
                                errorWidget: (_, __, ___) => const Icon(Icons.music_note, color: Colors.white),
                              ),
                            ),
                            title: Text(
                              video.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              video.channelTitle,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.play_circle_fill_rounded, color: AppTheme.primaryLight, size: 32),
                              onPressed: () {
                                ref.read(playerServiceProvider).playSingle(video);
                                context.push('/player', extra: video);
                              },
                            ),
                            onTap: () {
                              ref.read(playerServiceProvider).playSingle(video);
                              context.push('/player', extra: video);
                            },
                          );
                        },
                        childCount: videos.length,
                      ),
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

// ──────────────────────────────────────────────
// Square Music Card (Horizontal Scroll)
// ──────────────────────────────────────────────
class _SquareMusicCard extends StatelessWidget {
  final VideoItem video;
  final VoidCallback onTap;

  const _SquareMusicCard({required this.video, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 150,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Square Cover Art
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: CachedNetworkImage(
                imageUrl: video.thumbnailHighRes.isNotEmpty ? video.thumbnailHighRes : video.thumbnailUrl,
                width: 150,
                height: 150,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  width: 150,
                  height: 150,
                  color: const Color(0xFF1E1E2E),
                  child: const Icon(Icons.music_note, color: Colors.white24, size: 40),
                ),
                errorWidget: (_, __, ___) => Container(
                  width: 150,
                  height: 150,
                  color: const Color(0xFF1E1E2E),
                  child: const Icon(Icons.music_note, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Title
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

            // Artist
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
    );
  }
}
