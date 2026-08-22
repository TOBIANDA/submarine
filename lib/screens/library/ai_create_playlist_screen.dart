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

  int _songCount = 15;

  @override
  void dispose() {
    _descCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  List<String> _parseDirectSongList(String text) {
    final lines = text.split('\n');
    final ignoredPhrases = [
      'daftar lagu',
      'jangan lebih',
      'harus tepat',
      'deskripsi',
      'playlist',
      'tracklist',
      'judul lagu',
      'penyanyi',
    ];

    final songs = <String>[];
    for (var line in lines) {
      var clean = line.trim();
      if (clean.isEmpty) continue;

      final lower = clean.toLowerCase();
      if (ignoredPhrases.any((p) => lower == p || lower.startsWith(p) && !clean.contains('–') && !clean.contains('-'))) {
        continue;
      }

      if (clean.contains('–') || clean.contains('—') || clean.contains('-') || clean.contains(':')) {
        // Strip leading numbers like "1. " or "1) " without affecting song titles like "18 – One Direction"
        clean = clean.replaceAll(RegExp(r'^\s*\d+[\.\)]\s+'), '');
        if (clean.isNotEmpty) {
          songs.add(clean);
        }
      }
    }
    return songs;
  }

  Future<void> _generate() async {
    final desc = _descCtrl.text.trim();
    if (desc.isEmpty) return;

    setState(() {
      _step = _AiCreateStep.loading;
      _loadingMsg = '✨ Menyiapkan daftar lagu untuk kamu...';
      _error = null;
      _previewItems = [];
      _unchecked.clear();
    });

    try {
      final List<String> queries;
      final List<String> reasons;
      final String message;

      final directList = _parseDirectSongList(desc);
      if (directList.length >= 2) {
        // Direct list mode: match every song exactly from user input
        queries = directList.map((s) => '$s official audio').toList();
        reasons = List.generate(directList.length, (i) => 'Sesuai daftar kamu');
        message = 'Berhasil memuat ${directList.length} lagu sesuai daftar yang kamu minta!';
      } else {
        // AI prompt curation mode
        final curation = await AiService().curatePlaylist(desc, count: _songCount);
        queries = curation.queries;
        reasons = curation.reasons;
        message = curation.message;
      }

      setState(() => _loadingMsg = '🔍 Mencari ${queries.length} lagu di YouTube...');

      final items = <VideoItem>[];
      final matchedReasons = <String>[];
      final seen = <String>{};

      // Search YouTube in parallel chunks of 6 to prevent throttling
      for (int i = 0; i < queries.length; i += 6) {
        final end = (i + 6 > queries.length) ? queries.length : i + 6;
        final chunk = queries.sublist(i, end);
        final futures = chunk.map((q) => YoutubeService().searchVideos(q, maxResults: 1)).toList();
        final chunkResults = await Future.wait(futures);

        for (int j = 0; j < chunkResults.length; j++) {
          final qIndex = i + j;
          final batch = chunkResults[j];
          for (final v in batch) {
            if (!seen.contains(v.videoId)) {
              seen.add(v.videoId);
              items.add(v);
              matchedReasons.add(reasons[qIndex]);
            }
          }
        }
      }

      if (_nameCtrl.text.isEmpty) {
        if (directList.length >= 2) {
          _nameCtrl.text = 'Daftar Lagu Pilihan (${items.length} Lagu)';
        } else {
          final words = desc.split(' ').take(4).join(' ');
          _nameCtrl.text = words.isNotEmpty ? words : 'Playlist AI';
        }
      }

      setState(() {
        _previewItems = items;
        _aiMessage = message;
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Playlist "$name" (${finalItems.length} lagu) disimpan!'),
          backgroundColor: AppTheme.primary,
        ),
      );
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
            Icon(Icons.auto_awesome_rounded, color: AppTheme.aiColor, size: 20),
            SizedBox(width: 8),
            Text('Buat Playlist via AI',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          ],
        ),
      ),
      body: switch (_step) {
        _AiCreateStep.input => _InputView(
            descCtrl: _descCtrl,
            error: _error,
            songCount: _songCount,
            onSongCountChanged: (v) => setState(() => _songCount = v),
            onGenerate: _generate,
          ),
        _AiCreateStep.loading => _LoadingView(message: _loadingMsg),
        _AiCreateStep.preview => _PreviewView(
            aiMessage: _aiMessage,
            aiReasons: _aiReasons,
            items: _previewItems,
            unchecked: _unchecked,
            nameCtrl: _nameCtrl,
            onToggle: (i) => setState(() {
              if (_unchecked.contains(i)) {
                _unchecked.remove(i);
              } else {
                _unchecked.add(i);
              }
            }),
            onRegenerate: () => setState(() => _step = _AiCreateStep.input),
            onSave: _savePlaylist,
          ),
      },
    );
  }
}

// 
// Input View
// 
class _InputView extends StatelessWidget {
  final TextEditingController descCtrl;
  final String? error;
  final int songCount;
  final ValueChanged<int> onSongCountChanged;
  final VoidCallback onGenerate;

  const _InputView({
    required this.descCtrl,
    required this.error,
    required this.songCount,
    required this.onSongCountChanged,
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.aiColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.aiColor.withOpacity(0.4)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.psychology_rounded, size: 14, color: AppTheme.aiColor),
                SizedBox(width: 6),
                Text('AI Assistant & Smart Playlist Engine',
                    style: TextStyle(
                        color: AppTheme.aiColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Deskripsikan playlist atau tempel daftar lagumu',
            style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1.3),
          ),
          const SizedBox(height: 8),
          const Text(
            'Ketik tema/suasana, atau tempel daftar judul lagu & penyanyi secara langsung.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 20),

          // Textarea
          TextField(
            controller: descCtrl,
            maxLines: 7,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText:
                  'Contoh:\n- Lagu galau akustik Indonesia tahun 2000-an\n- Atau tempel daftar: "18 - One Direction, 8 Letters - Why Don\'t We..."',
              hintStyle:
                  const TextStyle(color: AppTheme.textMuted, fontSize: 13),
              filled: true,
              fillColor: AppTheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppTheme.divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppTheme.aiColor, width: 1.5),
              ),
            ),
          ),

          if (error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.error.withOpacity(0.3)),
              ),
              child: Text(error!,
                  style: const TextStyle(color: AppTheme.error, fontSize: 13)),
            ),
          ],

          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Jumlah Lagu AI:',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              Text('$songCount Lagu',
                  style: const TextStyle(
                      color: AppTheme.aiColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          Slider(
            value: songCount.toDouble(),
            min: 5,
            max: 60,
            divisions: 11,
            activeColor: AppTheme.aiColor,
            inactiveColor: AppTheme.surfaceVariant,
            label: '$songCount Lagu',
            onChanged: (v) => onSongCountChanged(v.round()),
          ),

          const SizedBox(height: 16),
          const Text('Contoh cepat:',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              'jazz santai buat sore',
              'workout EDM 10 lagu',
              'acoustic romance indo',
              'classical focus study',
            ].map((preset) => ActionChip(
                  label: Text(preset,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12)),
                  backgroundColor: AppTheme.surface,
                  side: const BorderSide(color: AppTheme.divider),
                  onPressed: () => descCtrl.text = preset,
                )).toList(),
          ),

          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onGenerate,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.aiColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.auto_awesome_rounded,
                  color: Colors.white, size: 20),
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

// 
// Loading View
// 
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
              'Sedang mencocokkan setiap lagu dari daftar...',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// 
// Preview View
// 
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
        if (aiMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.aiColor.withOpacity(0.1),
                border: Border.all(color: AppTheme.aiColor.withOpacity(0.3)),
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
                  const Icon(Icons.playlist_add_check_rounded, color: AppTheme.aiColor, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      aiMessage,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        
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
                                  const Icon(Icons.check_circle_rounded, size: 14, color: AppTheme.aiColor),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      aiReasons[i],
                                      style: const TextStyle(
                                        color: AppTheme.aiColor,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
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

