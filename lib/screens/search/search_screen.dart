// lib/screens/search/search_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';

import '../../providers/search_provider.dart';
import '../../providers/player_provider.dart';
import '../../models/video_item.dart';
import '../../theme/app_theme.dart';
import '../../widgets/add_to_playlist_sheet.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  final List<String> _quickTags = [
    'lofi hip hop study',
    'jazz cafe instrumental',
    'indie pop 2024',
    'classic rock hits',
    'acoustic guitar chill',
    'edm workout mix',
  ];

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (q.trim().isNotEmpty) {
        ref.read(searchProvider.notifier).search(q.trim());
      }
    });
  }

  void _searchTag(String tag) {
    _controller.text = tag;
    ref.read(searchProvider.notifier).search(tag);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Search Input Field ────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2E),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TextField(
                  controller: _controller,
                  onChanged: _onQueryChanged,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Cari lagu, artis, album...',
                    hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 14),
                    prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary, size: 22),
                    suffixIcon: _controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, color: AppTheme.textSecondary, size: 20),
                            onPressed: () {
                              _controller.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
            ),

            // ── Content (Suggestions or Results) ─────────────
            Expanded(
              child: _controller.text.isEmpty
                  ? _buildSuggestions()
                  : _buildResults(state),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Coba cari...',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _quickTags.map((tag) {
              return ActionChip(
                label: Text(
                  tag,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
                ),
                backgroundColor: const Color(0xFF1E1E2E),
                side: BorderSide.none,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                onPressed: () => _searchTag(tag),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(SearchState state) {
    if (state.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryLight),
      );
    }

    if (state.error != null) {
      return Center(
        child: Text(
          'Error: ${state.error}',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }

    if (state.results.isEmpty) {
      return const Center(
        child: Text(
          'Lagu tidak ditemukan',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 90, top: 4),
      itemCount: state.results.length,
      itemBuilder: (context, index) {
        final video = state.results[index];
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
            icon: const Icon(Icons.more_vert_rounded, color: AppTheme.textSecondary, size: 20),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (_) => AddToPlaylistSheet(video: video),
              );
            },
          ),
          onTap: () {
            ref.read(playerServiceProvider).playSingle(video);
            context.push('/player', extra: video);
          },
        );
      },
    );
  }
}
