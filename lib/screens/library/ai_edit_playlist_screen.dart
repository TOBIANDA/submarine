// lib/screens/library/ai_edit_playlist_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/playlist_provider.dart';
import '../../models/video_item.dart';
import '../../models/playlist.dart';
import '../../services/ai_service.dart';
import '../../services/youtube_service.dart';
import '../../services/db_service.dart';
import '../../widgets/video_list_tile.dart';
import '../../theme/app_theme.dart';

enum _AiEditStep { input, loading, preview }

class AiEditPlaylistScreen extends ConsumerStatefulWidget {
  final String playlistId;
  const AiEditPlaylistScreen({super.key, required this.playlistId});

  @override
  ConsumerState<AiEditPlaylistScreen> createState() =>
      _AiEditPlaylistScreenState();
}

class _AiEditPlaylistScreenState extends ConsumerState<AiEditPlaylistScreen> {
  final _instrCtrl = TextEditingController();
  _AiEditStep _step = _AiEditStep.input;
  String _loadingMsg = '';
  String? _error;

  // Preview data
  String _aiMessage = '';
  List<VideoItem> _keptItems = [];
  List<VideoItem> _removedItems = [];
  List<VideoItem> _newItems = [];
  List<String> _newReasons = [];

  final Set<int> _uncheckedRemoved = {};
  final Set<int> _uncheckedNew = {};

  @override
  void dispose() {
    _instrCtrl.dispose();
    super.dispose();
  }

  Future<void> _runEdit(Playlist playlist) async {
    final instruction = _instrCtrl.text.trim();
    if (instruction.isEmpty) return;

    setState(() {
      _step = _AiEditStep.loading;
      _loadingMsg = '?? AI sedang menganalisis playlist kamu...';
      _error = null;
    });

    try {
      final result = await AiService().editPlaylist(playlist.items, instruction);
      setState(() => _loadingMsg = '?? Mencari lagu baru di YouTube...');

      List<VideoItem> newItems = [];
      List<String> newReasons = [];

      if (result.newSongQueries.isNotEmpty) {
        final futures = result.newSongQueries
            .map((q) => YoutubeService().searchVideos(q, maxResults: 1))
            .toList();
        final results = await Future.wait(futures);
        final seen = <String>{...playlist.items.map((v) => v.videoId)};

        for (int i = 0; i < results.length; i++) {
          for (final v in results[i]) {
            if (!seen.contains(v.videoId)) {
              seen.add(v.videoId);
              newItems.add(v);
              newReasons.add(result.newSongReasons.length > i ? result.newSongReasons[i] : '');
            }
          }
        }
      }

      final keepSet = result.keepIndices.toSet();
      final keptItems = <VideoItem>[];
      final removedItems = <VideoItem>[];
      for (int i = 0; i < playlist.items.length; i++) {
        if (keepSet.contains(i)) {
          keptItems.add(playlist.items[i]);
        } else {
          removedItems.add(playlist.items[i]);
        }
      }

      setState(() {
        _aiMessage = result.message;
        _keptItems = keptItems;
        _removedItems = removedItems;
        _newItems = newItems;
        _newReasons = newReasons;
        _uncheckedRemoved.clear();
        _uncheckedNew.clear();
        _step = _AiEditStep.preview;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _step = _AiEditStep.input;
      });
    }
  }

  Future<void> _applyEdit(Playlist playlist) async {
    final finalItems = <VideoItem>[
      ..._keptItems,
      ...List.generate(_removedItems.length, (i) => i)
          .where((i) => _uncheckedRemoved.contains(i))
          .map((i) => _removedItems[i]),
      ...List.generate(_newItems.length, (i) => i)
          .where((i) => !_uncheckedNew.contains(i))
          .map((i) => _newItems[i]),
    ];

    try {
      await DbService().reorderPlaylistItems(playlist.id, finalItems);
      ref.invalidate(singlePlaylistProvider(playlist.id));
      ref.read(playlistProvider.notifier).refresh();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('? Playlist berhasil diedit oleh AI!'),
          backgroundColor: AppTheme.aiColor,
          behavior: SnackBarBehavior.floating,
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal menyimpan: $e'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlistAsync = ref.watch(singlePlaylistProvider(widget.playlistId));
    return playlistAsync.when(
      loading: () => const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(child: CircularProgressIndicator(color: AppTheme.aiColor)),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(child: Text('Error: $e')),
      ),
      data: (playlist) {
        if (playlist == null) {
          return const Scaffold(
            backgroundColor: AppTheme.background,
            body: Center(child: Text('Playlist tidak ditemukan.')),
          );
        }
        return _buildScaffold(context, playlist);
      },
    );
  }

  Widget _buildScaffold(BuildContext context, Playlist playlist) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.auto_awesome_rounded, color: AppTheme.aiColor, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Edit "${playlist.title}" via AI',
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _step == _AiEditStep.loading
            ? _LoadingView(message: _loadingMsg)
            : _step == _AiEditStep.preview
                ? _PreviewView(
                    playlist: playlist,
                    aiMessage: _aiMessage,
                    keptItems: _keptItems,
                    removedItems: _removedItems,
                    newItems: _newItems,
                    newReasons: _newReasons,
                    uncheckedRemoved: _uncheckedRemoved,
                    uncheckedNew: _uncheckedNew,
                    onToggleRemoved: (i) => setState(() =>
                        _uncheckedRemoved.contains(i)
                            ? _uncheckedRemoved.remove(i)
                            : _uncheckedRemoved.add(i)),
                    onToggleNew: (i) => setState(() =>
                        _uncheckedNew.contains(i)
                            ? _uncheckedNew.remove(i)
                            : _uncheckedNew.add(i)),
                    onRegenerate: () => setState(() => _step = _AiEditStep.input),
                    onApply: () => _applyEdit(playlist),
                  )
                : _InputView(
                    playlist: playlist,
                    ctrl: _instrCtrl,
                    error: _error,
                    onRun: () => _runEdit(playlist),
                  ),
      ),
    );
  }
}

// -- Input View --------------------------------------------------
class _InputView extends StatelessWidget {
  final Playlist playlist;
  final TextEditingController ctrl;
  final String? error;
  final VoidCallback onRun;

  const _InputView({
    required this.playlist,
    required this.ctrl,
    this.error,
    required this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: AppTheme.aiGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.psychology_rounded, color: Colors.white, size: 16),
                SizedBox(width: 6),
                Text('AI Playlist Editor',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Row(
              children: [
                const Icon(Icons.queue_music_rounded, color: AppTheme.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(playlist.title,
                          style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14)),
                      Text('${playlist.items.length} lagu',
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const Text('Apa yang ingin kamu ubah?',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.2)),
          const SizedBox(height: 6),
          const Text(
            'AI akan menambah, menghapus, atau menyesuaikan lagu sesuai instruksimu.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 20),

          TextField(
            controller: ctrl,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
            maxLines: 5,
            minLines: 3,
            decoration: const InputDecoration(
              hintText: 'e.g. "Tambah 5 lagu K-pop yang energik" atau "Hapus lagu yang terlalu slow"',
            ),
          ),

          if (error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
              ),
              child: Text(error!,
                  style: const TextStyle(color: AppTheme.error, fontSize: 13)),
            ),
          ],

          const SizedBox(height: 16),
          const Text('Contoh instruksi:',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              'Tambah 5 lagu K-pop',
              'Hapus yang terlalu slow',
              'Ganti semua dengan EDM',
              'Tambah 3 lagu jazz santai',
              'Hapus duplikat artis',
            ]
                .map((s) => ActionChip(
                      label: Text(s,
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 12)),
                      backgroundColor: AppTheme.surfaceVariant,
                      side: BorderSide.none,
                      onPressed: () => ctrl.text = s,
                    ))
                .toList(),
          ),

          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: playlist.items.isEmpty ? null : onRun,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.aiColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              icon: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
              label: const Text('Edit dengan AI',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

// -- Loading View -------------------------------------------------
class _LoadingView extends StatelessWidget {
  final String message;
  const _LoadingView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 64,
              height: 64,
              child: CircularProgressIndicator(color: AppTheme.aiColor, strokeWidth: 3),
            ),
            const SizedBox(height: 24),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            const Text('Ini mungkin butuh beberapa detik...',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

// -- Preview View -------------------------------------------------
class _PreviewView extends StatelessWidget {
  final Playlist playlist;
  final String aiMessage;
  final List<VideoItem> keptItems;
  final List<VideoItem> removedItems;
  final List<VideoItem> newItems;
  final List<String> newReasons;
  final Set<int> uncheckedRemoved;
  final Set<int> uncheckedNew;
  final ValueChanged<int> onToggleRemoved;
  final ValueChanged<int> onToggleNew;
  final VoidCallback onRegenerate;
  final VoidCallback onApply;

  const _PreviewView({
    required this.playlist,
    required this.aiMessage,
    required this.keptItems,
    required this.removedItems,
    required this.newItems,
    required this.newReasons,
    required this.uncheckedRemoved,
    required this.uncheckedNew,
    required this.onToggleRemoved,
    required this.onToggleNew,
    required this.onRegenerate,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final willRemoveCount = removedItems.length - uncheckedRemoved.length;
    final willAddCount = newItems.length - uncheckedNew.length;
    final finalCount = keptItems.length + uncheckedRemoved.length + willAddCount;

    return Column(
      children: [
        // AI Message
        if (aiMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.aiColor.withValues(alpha: 0.1),
                border: Border.all(color: AppTheme.aiColor.withValues(alpha: 0.3)),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                  bottomLeft: Radius.circular(4),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.psychology_rounded, color: AppTheme.aiColor, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(aiMessage,
                        style: const TextStyle(
                            color: AppTheme.textPrimary, fontSize: 13, height: 1.4)),
                  ),
                ],
              ),
            ),
          ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              if (willRemoveCount > 0)
                _SummaryChip(label: '-$willRemoveCount dihapus', color: AppTheme.error),
              if (willRemoveCount > 0 && willAddCount > 0) const SizedBox(width: 8),
              if (willAddCount > 0)
                _SummaryChip(label: '+$willAddCount ditambah', color: Colors.green),
              const Spacer(),
              Text('$finalCount lagu total',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: onRegenerate,
                icon: const Icon(Icons.refresh_rounded, size: 15, color: AppTheme.aiColor),
                label: const Text('Ulang', style: TextStyle(color: AppTheme.aiColor, fontSize: 12)),
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 100),
            children: [
              if (removedItems.isNotEmpty) ...[
                const _SectionHeader(
                  icon: Icons.remove_circle_outline_rounded,
                  color: AppTheme.error,
                  title: 'Lagu yang Dihapus AI',
                  subtitle: 'Centang untuk membatalkan penghapusan',
                ),
                ...List.generate(removedItems.length, (i) {
                  final willKeep = uncheckedRemoved.contains(i);
                  return _EditItemTile(
                    video: removedItems[i],
                    isChecked: !willKeep,
                    checkColor: AppTheme.error,
                    dimWhenChecked: true,
                    reason: null,
                    onToggle: () => onToggleRemoved(i),
                    badge: willKeep ? null : const _ItemBadge(label: 'HAPUS', color: AppTheme.error),
                  );
                }),
              ],

              if (newItems.isNotEmpty) ...[
                const _SectionHeader(
                  icon: Icons.add_circle_outline_rounded,
                  color: Colors.green,
                  title: 'Lagu Baru Ditambahkan AI',
                  subtitle: 'Hapus centang untuk tidak menambahkan',
                ),
                ...List.generate(newItems.length, (i) {
                  final willAdd = !uncheckedNew.contains(i);
                  return _EditItemTile(
                    video: newItems[i],
                    isChecked: willAdd,
                    checkColor: Colors.green,
                    dimWhenChecked: false,
                    reason: newReasons.length > i ? newReasons[i] : null,
                    onToggle: () => onToggleNew(i),
                    badge: willAdd ? const _ItemBadge(label: 'BARU', color: Colors.green) : null,
                  );
                }),
              ],

              if (keptItems.isNotEmpty) ...[
                const _SectionHeader(
                  icon: Icons.check_circle_outline_rounded,
                  color: AppTheme.primary,
                  title: 'Lagu yang Dipertahankan',
                  subtitle: null,
                ),
                ...keptItems.map((v) => Opacity(opacity: 0.55, child: VideoListTile(video: v))),
              ],
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onApply,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.aiColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              icon: const Icon(Icons.save_rounded, color: Colors.white),
              label: Text('Terapkan Perubahan ($finalCount lagu)',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;

  const _SectionHeader({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(title,
                  style: TextStyle(
                      color: color, fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 2),
              child: Text(subtitle!,
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            ),
          const SizedBox(height: 4),
          Divider(height: 1, color: color.withValues(alpha: 0.3)),
        ],
      ),
    );
  }
}

class _EditItemTile extends StatelessWidget {
  final VideoItem video;
  final bool isChecked;
  final Color checkColor;
  final bool dimWhenChecked;
  final String? reason;
  final VoidCallback onToggle;
  final Widget? badge;

  const _EditItemTile({
    required this.video,
    required this.isChecked,
    required this.checkColor,
    required this.dimWhenChecked,
    this.reason,
    required this.onToggle,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final dim = dimWhenChecked ? isChecked : !isChecked;
    return Opacity(
      opacity: dim ? 0.35 : 1.0,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: isChecked,
            onChanged: (_) => onToggle(),
            activeColor: checkColor,
            side: BorderSide(color: checkColor.withValues(alpha: 0.5)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    VideoListTile(video: video),
                    if (badge != null) Positioned(top: 8, right: 8, child: badge!),
                  ],
                ),
                if (reason != null && reason!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            size: 13, color: AppTheme.aiColor),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(reason!,
                              style: const TextStyle(
                                  color: AppTheme.aiColor,
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _ItemBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final Color color;
  const _SummaryChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
