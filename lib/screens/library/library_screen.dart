// lib/screens/library/library_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:uuid/uuid.dart';

import '../../providers/playlist_provider.dart';
import '../../models/playlist.dart';
import '../../theme/app_theme.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistAsync = ref.watch(playlistProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: const Text('Library',
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 22)),
            actions: [
              IconButton(
                icon: const Icon(Icons.add_rounded, color: AppTheme.primary),
                onPressed: () => _showCreateSheet(context, ref),
              ),
              const SizedBox(width: 4),
            ],
          ),
          playlistAsync.when(
            loading: () => const SliverFillRemaining(
              child: Center(
                  child: CircularProgressIndicator(color: AppTheme.primary)),
            ),
            error: (e, _) => SliverFillRemaining(
              child: Center(child: Text('Error: $e')),
            ),
            data: (playlists) {
              if (playlists.isEmpty) {
                return SliverFillRemaining(child: _EmptyLibrary(ref: ref));
              }
              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _PlaylistListItem(
                    playlist: playlists[i],
                    onTap: () =>
                        context.push('/library/${playlists[i].id}'),
                    onDelete: () => _confirmDelete(context, ref, playlists[i]),
                  ),
                  childCount: playlists.length,
                ),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateSheet(context, ref),
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Buat Playlist',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }

  void _showCreateSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreatePlaylistSheet(ref: ref),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, Playlist playlist) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Hapus Playlist?',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('Playlist "${playlist.title}" akan dihapus permanen.',
            style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal',
                  style: TextStyle(color: AppTheme.textMuted))),
          TextButton(
            onPressed: () {
              ref.read(playlistProvider.notifier).deletePlaylist(playlist.id);
              Navigator.pop(context);
            },
            child: const Text('Hapus',
                style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }
}

class _PlaylistListItem extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _PlaylistListItem(
      {required this.playlist, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(playlist.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppTheme.error.withValues(alpha: 0.15),
        child: const Icon(Icons.delete_rounded, color: AppTheme.error),
      ),
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      child: ListTile(
        onTap: onTap,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: playlist.coverThumbnail != null
              ? CachedNetworkImage(
                  imageUrl: playlist.coverThumbnail!,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover)
              : Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.queue_music_rounded,
                      color: Colors.white, size: 24)),
        ),
        title: Text(playlist.title,
            style: const TextStyle(
                color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
        subtitle: Row(
          children: [
            if (playlist.source == 'ai_curated')
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.auto_awesome_rounded,
                    color: AppTheme.aiColor, size: 11),
              ),
            Text(
              '${playlist.items.length} lagu • ${playlist.formattedTotalDuration}',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right_rounded,
            color: AppTheme.textMuted),
      ),
    );
  }
}

class _CreatePlaylistSheet extends StatefulWidget {
  final WidgetRef ref;
  const _CreatePlaylistSheet({required this.ref});

  @override
  State<_CreatePlaylistSheet> createState() => _CreatePlaylistSheetState();
}

class _CreatePlaylistSheetState extends State<_CreatePlaylistSheet> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: AppTheme.divider,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Buat Playlist Baru',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            // AI Option
            _CreateOption(
              icon: Icons.auto_awesome_rounded,
              iconColor: AppTheme.aiColor,
              gradient: AppTheme.aiGradient,
              title: 'Via AI ✨',
              subtitle: 'Deskripsikan mood, AI cariin lagunya',
              onTap: () {
                Navigator.pop(context);
                context.push('/library/ai-create');
              },
            ),
            const SizedBox(height: 12),
            // Manual Option — ambil rootContext sebelum pop agar tetap valid
            _CreateOption(
              icon: Icons.playlist_add_rounded,
              iconColor: AppTheme.primary,
              gradient: AppTheme.primaryGradient,
              title: 'Manual',
              subtitle: 'Buat kosong, tambah lagu sendiri',
              onTap: () async {
                // Simpan context sebelum sheet ditutup
                final rootContext = context;
                Navigator.pop(context);
                await _createManual(rootContext);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _createManual(BuildContext context) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Nama Playlist',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(hintText: 'e.g. Lagu Pagi'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Batal',
                  style: TextStyle(color: AppTheme.textMuted))),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, ctrl.text),
            child: const Text('Buat',
                style: TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );

    ctrl.dispose();

    if (result != null && result.trim().isNotEmpty) {
      final playlist = Playlist(
        id: const Uuid().v4(),
        title: result.trim(),
        createdAt: DateTime.now(),
        source: 'manual',
      );
      widget.ref.read(playlistProvider.notifier).addPlaylist(playlist);
    }
  }
}

class _CreateOption extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final LinearGradient gradient;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _CreateOption({
    required this.icon,
    required this.iconColor,
    required this.gradient,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15)),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: AppTheme.textMuted, size: 14),
          ],
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  final WidgetRef ref;
  const _EmptyLibrary({required this.ref});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              gradient: AppTheme.primaryGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.library_music_rounded,
                color: Colors.white, size: 36),
          ),
          const SizedBox(height: 20),
          const Text('Library Kosong',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Buat playlist pertama kamu!',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 14)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => context.push('/library/ai-create'),
            icon: const Icon(Icons.auto_awesome_rounded, size: 16),
            label: const Text('Buat dengan AI'),
          ),
        ],
      ),
    );
  }
}
