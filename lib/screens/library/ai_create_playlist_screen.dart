// lib/screens/library/ai_create_playlist_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../providers/playlist_provider.dart';
import '../../models/video_item.dart';
import '../../models/playlist.dart';
import '../../services/ai_service.dart';
import '../../services/youtube_service.dart';
import '../../widgets/video_list_tile.dart';
import '../../theme/app_theme.dart';

enum _AiCreateStep { input, loading, preview }

class AiCreatePlaylistScreen extends ConsumerStatefulWidget {
  const AiCreatePlaylistScreen({super.key});

  @override
  ConsumerState<AiCreatePlaylistScreen> createState() =>
      _AiCreatePlaylistScreenState();
}

class _AiCreatePlaylistScreenState
    extends ConsumerState<AiCreatePlaylistScreen> {
  final _descCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  _AiCreateStep _step = _AiCreateStep.input;
  String _loadingMsg = '';
  String? _error;
  List<VideoItem> _previewItems = [];
  final Set<int> _unchecked = {};
  String _aiMessage = '';
  List<String> _aiReasons = [];

  int _songCount = 10;

  @override
  void dispose() {
    _descCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final desc = _descCtrl.text.trim();
    if (desc.isEmpty) return;

    setState(() {
      _step = _AiCreateStep.loading;
      _loadingMsg = '🤖 AI sedang memilih lagu untuk kamu...';
      _error = null;
      _previewItems = [];
      _unchecked.clear();
    });

    try {
      // Step 1 – Ask Claude for search queries
      final curation = await AiService().curatePlaylist(desc, count: _songCount);

      setState(() =>
          _loadingMsg = '🔍 Mencari $_songCount lagu di YouTube...');

      // Step 2 – Search YouTube for each query in parallel (batched)
      final futures = curation.queries
          .map((q) => YoutubeService().searchVideos(q, maxResults: 1))
          .toList();
      final results = await Future.wait(futures);

      final items = <VideoItem>[];
      final matchedReasons = <String>[];
      final seen = <String>{};
      
      for (int i = 0; i < results.length; i++) {
        final batch = results[i];
        for (final v in batch) {
          if (!seen.contains(v.videoId)) {
            seen.add(v.videoId);
            items.add(v);
            matchedReasons.add(curation.reasons[i]);
          }
        }
      }

      // Auto-fill playlist name from description
      if (_nameCtrl.text.isEmpty) {
        final words = desc.split(' ').take(4).join(' ');
        _nameCtrl.text = words;
      }

      setState(() {
        _previewItems = items;
        _aiMessage = curation.message;
        _aiReasons = matchedReasons;
        _step = _AiCreateStep.preview;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _step = _AiCreateStep.input;
      });
    }
  }

  Future<void> _savePlaylist() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    final finalItems = _previewItems
        .where((v) => !_unchecked.contains(_previewItems.indexOf(v)))
        .toList();

    final playlist = Playlist(
      id: const Uuid().v4(),
      title: name,
      createdAt: DateTime.now(),
      source: 'ai_curated',
      items: finalItems,
    );

    await ref.read(playlistProvider.notifier).addPlaylist(playlist);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✨ Playlist berhasil dibuat!'),
        backgroundColor: AppTheme.aiColor,
        behavior: SnackBarBehavior.floating,
      ));
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome_rounded,
                color: AppTheme.aiColor, size: 20),
            SizedBox(width: 8),
            Text('Buat Playlist via AI'),
          ],
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _step == _AiCreateStep.loading
            ? _LoadingView(message: _loadingMsg)
            : _step == _AiCreateStep.preview
                ? _PreviewView(
                    aiMessage: _aiMessage,
                    aiReasons: _aiReasons,
                    items: _previewItems,
                    unchecked: _unchecked,
                    nameCtrl: _nameCtrl,
                    onToggle: (i) => setState(() => _unchecked.contains(i)
                        ? _unchecked.remove(i)
                        : _unchecked.add(i)),
                    onRegenerate: () =>
                        setState(() => _step = _AiCreateStep.input),
                    onSave: _savePlaylist,
                  )
                : _InputView(
                    ctrl: _descCtrl,
                    error: _error,
                    songCount: _songCount,
                    onCountChanged: (val) => setState(() => _songCount = val),
                    onGenerate: _generate,
                  ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Input View
// ──────────────────────────────────────────────────────────────
class _InputView extends StatelessWidget {
  final TextEditingController ctrl;
  final String? error;
  final int songCount;
  final ValueChanged<int> onCountChanged;
  final VoidCallback onGenerate;

  const _InputView({
    required this.ctrl,
    this.error,
    required this.songCount,
    required this.onCountChanged,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: AppTheme.aiGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.psychology_rounded,
                    color: Colors.white, size: 16),
                SizedBox(width: 6),
                Text('Powered by Claude AI',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),

          const SizedBox(height: 20),
          const Text(
            'Deskripsikan playlist\nyang kamu inginkan',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'AI akan mencarikan lagu-lagu YouTube yang sesuai.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),

          const SizedBox(height: 24),
          TextField(
            controller: ctrl,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
            maxLines: 5,
            minLines: 3,
            decoration: const InputDecoration(
              hintText:
                  'e.g. "lo-fi buat belajar, 10 lagu, jangan yang terlalu monoton"',
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
                  style: const TextStyle(
                      color: AppTheme.error, fontSize: 13)),
            ),
          ],

          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Jumlah Lagu:',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
              ),
              Text(
                '$songCount Lagu',
                style: const TextStyle(
                    color: AppTheme.aiColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Slider(
            value: songCount.toDouble(),
            min: 5,
            max: 25,
            divisions: 4,
            activeColor: AppTheme.aiColor,
            inactiveColor: AppTheme.surface.withValues(alpha: 0.5),
            label: songCount.toString(),
            onChanged: (val) => onCountChanged(val.toInt()),
          ),

          const SizedBox(height: 16),
          // Example chips
          const Text('Contoh:',
              style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              'jazz santai buat sore',
              'workout EDM 10 lagu',
              'acoustic romance indo',
              'classical focus study',
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
              onPressed: onGenerate,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.aiColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              icon: const Icon(Icons.auto_awesome_rounded,
                  color: Colors.white),
              label: const Text('Generate Playlist',
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

// ──────────────────────────────────────────────────────────────
// Loading View
// ──────────────────────────────────────────────────────────────
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
              child: CircularProgressIndicator(
                color: AppTheme.aiColor,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ini mungkin butuh beberapa detik...',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Preview View
// ──────────────────────────────────────────────────────────────
class _PreviewView extends StatelessWidget {
  final String aiMessage;
  final List<String> aiReasons;
  final List<VideoItem> items;
  final Set<int> unchecked;
  final TextEditingController nameCtrl;
  final ValueChanged<int> onToggle;
  final VoidCallback onRegenerate;
  final VoidCallback onSave;

  const _PreviewView({
    required this.aiMessage,
    required this.aiReasons,
    required this.items,
    required this.unchecked,
    required this.nameCtrl,
    required this.onToggle,
    required this.onRegenerate,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final selectedCount = items.length - unchecked.length;
    return Column(
      children: [
        // AI Message Box
        if (aiMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(16),
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      aiMessage,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        
        // Playlist name input
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: TextField(
            controller: nameCtrl,
            style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 16),
            decoration: const InputDecoration(
              prefixIcon:
                  Icon(Icons.edit_rounded, color: AppTheme.textMuted, size: 18),
              hintText: 'Nama Playlist',
            ),
          ),
        ),
        // Count + header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text(
                '$selectedCount dari ${items.length} lagu dipilih',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onRegenerate,
                icon: const Icon(Icons.refresh_rounded,
                    size: 15, color: AppTheme.aiColor),
                label: const Text('Ulang',
                    style: TextStyle(color: AppTheme.aiColor, fontSize: 13)),
              ),
            ],
          ),
        ),
        // List
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final isChecked = !unchecked.contains(i);
              return Row(
                children: [
                  Checkbox(
                    value: isChecked,
                    onChanged: (_) => onToggle(i),
                    activeColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.textMuted),
                  ),
                  Expanded(
                    child: Opacity(
                      opacity: isChecked ? 1.0 : 0.4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          VideoListTile(video: items[i]),
                          if (aiReasons.length > i && aiReasons[i].isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.info_outline_rounded, size: 14, color: AppTheme.aiColor),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      aiReasons[i],
                                      style: const TextStyle(
                                        color: AppTheme.aiColor,
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        // Save button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: selectedCount == 0 ? null : onSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              icon: const Icon(Icons.save_rounded, color: Colors.white),
              label: Text(
                'Simpan Playlist ($selectedCount lagu)',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

