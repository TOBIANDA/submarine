// lib/screens/profile/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../providers/player_provider.dart';
import '../../providers/history_provider.dart';
import '../../models/play_history.dart';
import '../../services/db_service.dart';
import '../../theme/app_theme.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(historyProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(
            pinned: true,
            title: Text('Profil & Riwayat',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 22)),
          ),

          // ── Stats row ──────────────────────────
          historyAsync.when(
            loading: () => const SliverToBoxAdapter(child: SizedBox()),
            error: (_, __) => const SliverToBoxAdapter(child: SizedBox()),
            data: (history) => SliverToBoxAdapter(
              child: _StatsRow(totalPlayed: history.length),
            ),
          ),

          // ── Settings Section ───────────────────
          const SliverToBoxAdapter(child: _SectionTitle(title: 'Pengaturan')),
          SliverToBoxAdapter(
            child: _SettingsCard(),
          ),

          // ── History Section ────────────────────
          const SliverToBoxAdapter(
              child: _SectionTitle(title: 'Riwayat Pemutaran')),

          historyAsync.when(
            loading: () => const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                    child: CircularProgressIndicator(color: AppTheme.primary)),
              ),
            ),
            error: (e, _) => SliverToBoxAdapter(
              child: Center(child: Text('Error: $e')),
            ),
            data: (history) {
              if (history.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(Icons.history_rounded,
                            color: AppTheme.textMuted, size: 48),
                        SizedBox(height: 12),
                        Text('Belum ada riwayat.',
                            style: TextStyle(color: AppTheme.textMuted)),
                      ],
                    ),
                  ),
                );
              }
              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _HistoryItem(
                    history: history[i],
                    onPlay: () {
                      final item = history[i].toVideoItem();
                      ref.read(playerServiceProvider).playSingle(item);
                      ref.read(playerServiceProvider.notifier).playSingle(item);
                    },
                  ),
                  childCount: history.length,
                ),
              );
            },
          ),

          // ── Clear history ──────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              child: OutlinedButton.icon(
                onPressed: () async {
                  await DbService().clearHistory();
                  ref.invalidate(historyProvider);
                  ref.invalidate(lastPlayedProvider);
                },
                icon: const Icon(Icons.delete_outline_rounded,
                    color: AppTheme.error),
                label: const Text('Hapus Semua Riwayat',
                    style: TextStyle(color: AppTheme.error)),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.error)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final int totalPlayed;
  const _StatsRow({required this.totalPlayed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          _StatChip(
              icon: Icons.play_circle_rounded,
              label: '$totalPlayed',
              subtitle: 'Diputar',
              color: AppTheme.primary),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;

  const _StatChip(
      {required this.icon,
      required this.label,
      required this.subtitle,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              Text(subtitle,
                  style: const TextStyle(
                      color: AppTheme.textMuted, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatefulWidget {
  @override
  State<_SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends State<_SettingsCard> {
  String _quality = 'auto';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _quality = prefs.getString('video_quality') ?? 'auto');
  }

  Future<void> _save(String q) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('video_quality', q);
    setState(() => _quality = q);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.hd_rounded, color: AppTheme.primary),
            title: const Text('Kualitas Video Default',
                style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text(_qualityLabel(_quality),
                style: const TextStyle(
                    color: AppTheme.textMuted, fontSize: 12)),
            trailing:
                const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
            onTap: () => _showQualityPicker(context),
          ),
          const Divider(height: 1, color: AppTheme.divider),
          ListTile(
            leading: const Icon(Icons.download_done_rounded, color: Color(0xFF4CAF50)),
            title: const Text('Lagu Offline',
                style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: const Text('Kelola lagu yang disimpan',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            trailing:
                const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
            onTap: () => context.push('/profile/downloads'),
          ),
          const Divider(height: 1, color: AppTheme.divider),
          const ListTile(
            leading:
                Icon(Icons.info_outline_rounded, color: AppTheme.textMuted),
            title: Text('Versi Aplikasi',
                style: TextStyle(color: AppTheme.textPrimary)),
            trailing: Text('1.0.0',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  String _qualityLabel(String q) {
    switch (q) {
      case 'hd720':
        return 'HD 720p';
      case 'hd1080':
        return 'Full HD 1080p';
      case 'small':
        return 'Hemat Data (360p)';
      default:
        return 'Otomatis';
    }
  }

  void _showQualityPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          const Text('Kualitas Video',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final (value, label) in [
            ('auto', 'Otomatis'),
            ('hd720', 'HD 720p'),
            ('hd1080', 'Full HD 1080p'),
            ('small', 'Hemat Data (360p)'),
          ])
            ListTile(
              title: Text(label,
                  style: const TextStyle(color: AppTheme.textPrimary)),
              trailing: _quality == value
                  ? const Icon(Icons.check_rounded, color: AppTheme.primary)
                  : null,
              onTap: () {
                _save(value);
                Navigator.pop(context);
              },
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5),
      ),
    );
  }
}

class _HistoryItem extends StatelessWidget {
  final PlayHistory history;
  final VoidCallback onPlay;

  const _HistoryItem({required this.history, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onPlay,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedNetworkImage(
          imageUrl: history.thumbnailUrl,
          width: 56,
          height: 42,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => Container(
            width: 56,
            height: 42,
            color: AppTheme.surfaceVariant,
            child: const Icon(Icons.music_note_rounded,
                color: AppTheme.textMuted),
          ),
        ),
      ),
      title: Text(
        history.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
      ),
      subtitle: Text(
        history.channelTitle,
        style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.play_arrow_rounded,
            color: AppTheme.primary, size: 22),
        onPressed: onPlay,
      ),
    );
  }
}
