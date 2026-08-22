// lib/screens/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../providers/recommendation_provider.dart';
import '../../providers/player_provider.dart';
import '../../models/video_item.dart';
import '../../theme/app_theme.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Selamat pagi,';
    if (hour < 17) return 'Selamat siang,';
    return 'Selamat malam,';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeCategory = ref.watch(activeCategoryProvider);
    final dailyMixAsync = ref.watch(dailyMixProvider);
    final recommendationAsync = ref.watch(recommendationProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(dailyMixProvider);
            ref.invalidate(recommendationProvider);
          },
          color: AppTheme.primaryLight,
          backgroundColor: AppTheme.surfaceVariant,
          child: CustomScrollView(
            slivers: [
              // ── Header (Greeting + Title + Icons) ─────────────────────
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

              // ── Category Pills (All, Trending, Music, Gaming, News, Live) ──
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 38,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: HomeCategory.values.length,
                    itemBuilder: (context, index) {
                      final cat = HomeCategory.values[index];
                      final isSelected = activeCategory == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () {
                            ref.read(activeCategoryProvider.notifier).state = cat;
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF6C4CE0) : const Color(0xFF1E1E2E),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF8B6EF3) : Colors.white.withValues(alpha: 0.05),
                              ),
                            ),
                            child: Text(
                              cat.label,
                              style: TextStyle(
                                color: isSelected ? Colors.white : AppTheme.textSecondary,
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // ── AI Playlist Banner Quick Action ─────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: GestureDetector(
                    onTap: () => context.push('/library/ai-create'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF6C4CE0).withValues(alpha: 0.35),
                            const Color(0xFF25D9A0).withValues(alpha: 0.15),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF6C4CE0).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF25D9A0), Color(0xFF1FBF9C)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Buat Playlist Otomatis AI',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Ketik suasana hati atau tema musik favoritmu',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: Colors.white54),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── Section: Daily Mix Untukmu (Taste Clustering) ─────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.stars_rounded, color: Color(0xFF25D9A0), size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Daily Mix Untukmu',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Taste Engine',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Horizontal Cards (Daily Mix) ──────────────────────────
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 210,
                  child: dailyMixAsync.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(color: AppTheme.primaryLight),
                    ),
                    error: (e, _) => Center(
                      child: Text('Gagal memuat Daily Mix: $e', style: const TextStyle(color: AppTheme.textSecondary)),
                    ),
                    data: (videos) {
                      if (videos.isEmpty) {
                        return const Center(
                          child: Text('Belum ada riwayat lagu untuk Daily Mix', style: TextStyle(color: AppTheme.textSecondary)),
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
                              ref.read(playerServiceProvider).loadQueue(videos, initialIndex: index);
                              context.push('/player', extra: video);
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ),

              // ── Section: Rekomendasi & Populer ────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.trending_up_rounded, color: Color(0xFF6C4CE0), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        activeCategory == HomeCategory.all ? 'Rekomendasi Teratas' : 'Kategori ${activeCategory.label}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Vertical Tracks List (Rekomendasi Kategori) ────────────
              recommendationAsync.when(
                loading: () => const SliverToBoxAdapter(
                  child: SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator(color: AppTheme.primaryLight)),
                  ),
                ),
                error: (err, _) => SliverToBoxAdapter(
                  child: Center(child: Text('Gagal memuat: $err', style: const TextStyle(color: AppTheme.textSecondary))),
                ),
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
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
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
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.play_circle_fill_rounded, color: AppTheme.primaryLight, size: 30),
                                  onPressed: () {
                                    ref.read(playerServiceProvider).loadQueue(videos, initialIndex: index);
                                    context.push('/player', extra: video);
                                  },
                                ),
                              ],
                            ),
                            onTap: () {
                              ref.read(playerServiceProvider).loadQueue(videos, initialIndex: index);
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

// ── Square Music Card for Horizontal Lists ──────────────────────────────
class _SquareMusicCard extends StatelessWidget {
  final VideoItem video;
  final VoidCallback onTap;

  const _SquareMusicCard({
    required this.video,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Album Art
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: CachedNetworkImage(
                    imageUrl: video.thumbnailUrl,
                    width: 140,
                    height: 140,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      width: 140,
                      height: 140,
                      color: const Color(0xFF1E1E2E),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      width: 140,
                      height: 140,
                      color: const Color(0xFF1E1E2E),
                      child: const Icon(Icons.music_note, color: Colors.white54),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Song Title
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

            // Artist Name
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
