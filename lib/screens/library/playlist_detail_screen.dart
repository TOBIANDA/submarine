// lib/screens/library/playlist_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../providers/playlist_provider.dart';
import '../../providers/player_provider.dart';
import '../../providers/download_provider.dart';
import '../../models/video_item.dart';
import '../../models/playlist.dart';
import '../../services/db_service.dart';
import '../../services/ai_service.dart';
import '../../services/youtube_service.dart';
import '../../widgets/video_list_tile.dart';
import '../../theme/app_theme.dart';

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  final String playlistId;
  const PlaylistDetailScreen({super.key, required this.playlistId});

  @override
  ConsumerState<PlaylistDetailScreen> createState() =>
      _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState
    extends ConsumerState<PlaylistDetailScreen> {
  bool _isAiReordering = false;

  @override
  Widget build(BuildContext context) {
    final playlistAsync = ref.watch(singlePlaylistProvider(widget.playlistId));

    return playlistAsync.when(
      loading: () => const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
            child: CircularProgressIndicator(color: AppTheme.primary)),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(child: Text('Error: $e')),
      ),
      data: (playlist) {
        if (playlist == null) {
          return const Scaffold(
            backgroundColor: AppTheme.background,
            body: Center(
                child: Text('Playlist tidak ditemukan.',
                    style: TextStyle(color: AppTheme.textMuted))),
          );
        }
        return _buildBody(context, playlist);
      },
    );
  }

  Widget _buildBody(BuildContext context, Playlist playlist) {
    final player = ref.watch(playerServiceProvider);
    final currentVideo = ref.watch(currentVideoProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddSongsSheet(context, playlist),
        backgroundColor: AppTheme.primary,
        tooltip: 'Tambah Lagu',
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: CustomScrollView(
        slivers: [
          // ── Header ─────────────────────────────
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: AppTheme.background,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => context.pop(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_rounded, color: AppTheme.textSecondary),
                tooltip: 'Ubah Nama',
                onPressed: () => _showRenameDialog(context, playlist),
              ),
              IconButton(
                icon: _isAiReordering
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppTheme.aiColor))
                    : const Icon(Icons.swap_vert_rounded,
                        color: AppTheme.aiColor),
                tooltip: 'AI Urutkan Ulang',
                onPressed: playlist.items.length < 2
                    ? null
                    : () => _showAiReorderDialog(context, playlist),
              ),
              IconButton(
                icon: const Icon(Icons.auto_awesome_rounded,
                    color: AppTheme.aiColor),
                tooltip: 'AI Edit Playlist',
                onPressed: playlist.items.isEmpty
                    ? null
                    : () => context.push('/library/${playlist.id}/ai-edit'),
              ),
              const SizedBox(width: 4),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Cover image
                  playlist.coverThumbnail != null
                      ? CachedNetworkImage(
                          imageUrl: playlist.coverThumbnail!,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          decoration: const BoxDecoration(
                              gradient: AppTheme.playerGradient)),
                  // Gradient overlay
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          AppTheme.background.withValues(alpha: 0.95),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.3, 1.0],
                      ),
                    ),
                  ),
                  // Info overlay
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (playlist.source == 'ai_curated')
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.aiColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color:
                                      AppTheme.aiColor.withValues(alpha: 0.4)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.auto_awesome_rounded,
                                    color: AppTheme.aiColor, size: 11),
                                SizedBox(width: 4),
                                Text('AI Curated',
                                    style: TextStyle(
                                        color: AppTheme.aiColor,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          playlist.title,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${playlist.items.length} lagu • ${playlist.formattedTotalDuration}',
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Play Controls ──────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: playlist.items.isEmpty
                          ? null
                          : () {
                              player.loadQueue(playlist.items,
                                  startIndex: 0, playlistId: playlist.id);
                              context.push('/player', extra: playlist.items.first);
                            },
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: const Text('Putar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: playlist.items.isEmpty
                          ? null
                          : () {
                              player.loadQueue(playlist.items,
                                  startIndex: 0, playlistId: playlist.id);
                              player.toggleShuffle();
                              context.push('/player', extra: playlist.items.first);
                            },
                      icon: const Icon(Icons.shuffle_rounded, size: 20),
                      label: const Text('Acak'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.surfaceVariant,
                        foregroundColor: AppTheme.textPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: playlist.items.isEmpty
                        ? null
                        : () {
                            ref.read(activeDownloadsProvider.notifier).downloadAll(playlist.items);
                          },
                    icon: const Icon(Icons.download_rounded),
                    tooltip: 'Unduh Semua',
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.surfaceVariant,
                      foregroundColor: AppTheme.primary,
                      padding: const EdgeInsets.all(12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Reorderable List ───────────────────
          playlist.items.isEmpty
              ? SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.queue_music_rounded,
                            color: AppTheme.textMuted, size: 48),
                        const SizedBox(height: 12),
                        const Text('Playlist kosong.',
                            style: TextStyle(
                                color: AppTheme.textMuted,
                                fontWeight: FontWeight.w600,
                                fontSize: 15)),
                        const SizedBox(height: 6),
                        const Text('Tekan + untuk menambah lagu.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppTheme.textMuted)),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () =>
                              _showAddSongsSheet(context, playlist),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Tambah Lagu'),
                        ),
                      ],
                    ),
                  ),
                )
              : SliverReorderableList(
                  onReorderItem: (oldIndex, newIndex) =>
                      _onReorder(playlist, oldIndex, newIndex),
                  itemCount: playlist.items.length,
                  itemBuilder: (_, i) {
                    final video = playlist.items[i];
                    final isActive =
                        currentVideo?.videoId == video.videoId;
                    return VideoListTile(
                      key: Key('${playlist.id}_$i'),
                      video: video,
                      isPlaying: isActive,
                      showDragHandle: false, // Turn off default handle
                      leading: ReorderableDragStartListener(
                        index: i,
                        child: const Icon(Icons.drag_handle_rounded, color: AppTheme.textMuted, size: 20),
                      ),
                      onTap: () {
                        player.loadQueue(playlist.items,
                            startIndex: i, playlistId: playlist.id);
                        context.push('/player', extra: video);
                      },
                      onAddToQueue: () => player.addToQueue(video),
                      onAddToPlaylist: null,
                    );
                  },
                ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  // ─── Rename ───────────────────────────────────────────────

  void _showRenameDialog(BuildContext context, Playlist playlist) {
    final ctrl = TextEditingController(text: playlist.title);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Ubah Nama Playlist',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 18)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Nama Playlist',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Batal',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              final newName = ctrl.text.trim();
              if (newName.isNotEmpty && newName != playlist.title) {
                ref.read(playlistProvider.notifier).renamePlaylist(playlist.id, newName);
              }
              context.pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  // ─── Add Songs Sheet ──────────────────────────────────────

  void _showAddSongsSheet(BuildContext context, Playlist playlist) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddSongsSheet(playlist: playlist, ref: ref),
    );
  }

  // ─── Reorder ──────────────────────────────────────────────

  Future<void> _onReorder(
      Playlist playlist, int oldIndex, int newIndex) async {
    final items = List<VideoItem>.from(playlist.items);
    // onReorderItem already adjusts newIndex for removed item
    final item = items.removeAt(oldIndex);
    items.insert(newIndex, item);

    await DbService().reorderPlaylistItems(playlist.id, items);
    ref.invalidate(singlePlaylistProvider(playlist.id));
    ref.read(playlistProvider.notifier).refresh();
  }

  // ─── AI Reorder ───────────────────────────────────────────

  void _showAiReorderDialog(BuildContext context, Playlist playlist) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Row(
          children: [
            const Icon(Icons.auto_awesome_rounded,
                color: AppTheme.aiColor, size: 20),
            const SizedBox(width: 8),
            const Text('AI Urutkan Ulang',
                style: TextStyle(color: AppTheme.textPrimary)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Beri instruksi bagaimana kamu ingin playlist diurutkan:',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'e.g. "taruh yang paling upbeat di akhir buat penutup"',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.aiColor),
            onPressed: () async {
              final instruction = ctrl.text.trim();
              if (instruction.isEmpty) return;
              Navigator.pop(context);
              await _doAiReorder(playlist, instruction);
            },
            child: const Text('Urutkan'),
          ),
        ],
      ),
    );
  }

  Future<void> _doAiReorder(Playlist playlist, String instruction) async {
    setState(() => _isAiReordering = true);
    try {
      final newOrder =
          await AiService().reorderPlaylist(playlist.items, instruction);

      if (newOrder.length != playlist.items.length) {
        throw Exception('AI returned wrong number of indices');
      }

      final reordered = newOrder.map((i) => playlist.items[i]).toList();
      await DbService().reorderPlaylistItems(playlist.id, reordered);
      ref.invalidate(singlePlaylistProvider(playlist.id));
      ref.read(playlistProvider.notifier).refresh();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✨ Playlist berhasil diurutkan oleh AI!'),
          backgroundColor: AppTheme.aiColor,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal: $e'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isAiReordering = false);
    }
  }
}

// ──────────────────────────────────────────────────────────────
// Add Songs Sheet — search & add songs to playlist
// ──────────────────────────────────────────────────────────────
class _AddSongsSheet extends StatefulWidget {
  final Playlist playlist;
  final WidgetRef ref;

  const _AddSongsSheet({required this.playlist, required this.ref});

  @override
  State<_AddSongsSheet> createState() => _AddSongsSheetState();
}

class _AddSongsSheetState extends State<_AddSongsSheet> {
  final _ctrl = TextEditingController();
  List<VideoItem> _results = [];
  bool _isLoading = false;
  String? _error;
  final Set<String> _addedIds = {};

  @override
  void initState() {
    super.initState();
    // Pre-fill added set with existing songs
    _addedIds.addAll(widget.playlist.items.map((v) => v.videoId));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await YoutubeService().searchVideos(q);
      setState(() => _results = results);
    } catch (e) {
      setState(() => _error = 'Pencarian gagal: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addSong(VideoItem video) async {
    if (_addedIds.contains(video.videoId)) return;
    setState(() => _addedIds.add(video.videoId));
    await DbService().addItemToPlaylist(widget.playlist.id, video);
    widget.ref.invalidate(singlePlaylistProvider(widget.playlist.id));
    widget.ref.read(playlistProvider.notifier).refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${video.title}" ditambahkan!'),
          backgroundColor: AppTheme.primary,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.add_circle_rounded,
                      color: AppTheme.primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tambah ke "${widget.playlist.title}"',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: AppTheme.textMuted),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Cari lagu untuk ditambahkan...',
                  prefixIcon:
                      const Icon(Icons.search_rounded, color: AppTheme.textMuted),
                  suffixIcon: _ctrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded,
                              color: AppTheme.textMuted),
                          onPressed: () {
                            _ctrl.clear();
                            setState(() => _results = []);
                          },
                        )
                      : null,
                ),
                onChanged: (q) {
                  setState(() {});
                  _search(q);
                },
                textInputAction: TextInputAction.search,
                onSubmitted: _search,
              ),
            ),
            const Divider(height: 1, color: AppTheme.divider),
            // Results
            Expanded(
              child: Builder(builder: (context) {
                if (_isLoading) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.primary));
                }
                if (_error != null) {
                  return Center(
                      child: Text(_error!,
                          style: const TextStyle(color: AppTheme.error)));
                }
                if (_results.isEmpty && _ctrl.text.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_rounded,
                            color: AppTheme.textMuted, size: 48),
                        SizedBox(height: 12),
                        Text('Ketik untuk mencari lagu',
                            style: TextStyle(color: AppTheme.textMuted)),
                      ],
                    ),
                  );
                }
                if (_results.isEmpty) {
                  return const Center(
                    child: Text('Tidak ada hasil.',
                        style: TextStyle(color: AppTheme.textMuted)),
                  );
                }
                return ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: _results.length,
                  itemBuilder: (_, i) {
                    final video = _results[i];
                    final isAdded = _addedIds.contains(video.videoId);
                    return VideoListTile(
                      video: video,
                      onTap: isAdded ? null : () => _addSong(video),
                      leading: isAdded
                          ? Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: AppTheme.primary
                                    .withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check_rounded,
                                  color: AppTheme.primary, size: 18),
                            )
                          : GestureDetector(
                              onTap: () => _addSong(video),
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: AppTheme.primary
                                      .withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.add_rounded,
                                    color: AppTheme.primary, size: 18),
                              ),
                            ),
                    );
                  },
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
