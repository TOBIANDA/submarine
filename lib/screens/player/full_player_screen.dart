// lib/screens/player/full_player_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:just_audio/just_audio.dart';

import '../../models/video_item.dart';
import '../../providers/player_provider.dart';
import '../../services/player_service.dart' as player_service_mode;
import '../../services/player_service.dart' show PlayerService;
import '../../services/db_service.dart';
import '../../models/playlist.dart';
import '../../theme/app_theme.dart';
import '../../widgets/add_to_playlist_sheet.dart';

class FullPlayerScreen extends ConsumerStatefulWidget {
  final VideoItem video;

  const FullPlayerScreen({super.key, required this.video});

  @override
  ConsumerState<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends ConsumerState<FullPlayerScreen> {
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _checkFavorite();
  }

  Future<void> _checkFavorite() async {
    final fav = await DbService().isFavorite(widget.video.videoId);
    if (mounted) setState(() => _isFavorite = fav);
  }

  Future<void> _toggleFavorite() async {
    final newFav = await DbService().toggleFavorite(widget.video);
    if (mounted) {
      setState(() => _isFavorite = newFav);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newFav ? 'Ditambahkan ke Favorit' : 'Dihapus dari Favorit'),
          duration: const Duration(seconds: 1),
          backgroundColor: AppTheme.surfaceVariant,
        ),
      );
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerServiceProvider);
    final currentVideo = player.currentVideo ?? widget.video;
    final audioPlayer = player.audioPlayer;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.playerGradient,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Column(
              children: [
                // ── Top Bar ─────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 34),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Column(
                      children: [
                        const Text(
                          'MEMUTAR DARI PLAYLIST',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 10,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Submarine Mix',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 24),
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          backgroundColor: Colors.transparent,
                          isScrollControlled: true,
                          builder: (_) => AddToPlaylistSheet(video: currentVideo),
                        );
                      },
                    ),
                  ],
                ),

                const Spacer(flex: 1),

                // ── Giant Album Art (Square with subtle shadow) ──
                Hero(
                  tag: 'player_album_art_${currentVideo.videoId}',
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.82,
                    height: MediaQuery.of(context).size.width * 0.82,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6C4CE0).withValues(alpha: 0.25),
                          blurRadius: 30,
                          offset: const Offset(0, 15),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.6),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: CachedNetworkImage(
                        imageUrl: currentVideo.thumbnailHighRes.isNotEmpty
                            ? currentVideo.thumbnailHighRes
                            : currentVideo.thumbnailUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: const Color(0xFF1E1E2E),
                          child: const Center(
                            child: Icon(Icons.music_note, color: Colors.white24, size: 80),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: const Color(0xFF1E1E2E),
                          child: const Center(
                            child: Icon(Icons.music_note, color: Colors.white, size: 80),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const Spacer(flex: 1),

                // ── Track Title & Artist & Favorite Button ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentVideo.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            currentVideo.channelTitle,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: _isFavorite ? const Color(0xFF25D9A0) : AppTheme.textSecondary,
                        size: 28,
                      ),
                      onPressed: _toggleFavorite,
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // ── Progress Bar & Timestamps ────────────────
                StreamBuilder<Duration>(
                    stream: player.positionStream,
                    builder: (context, snapshot) {
                      final position = snapshot.data ?? Duration.zero;
                      final totalDuration = player.duration ??
                          (currentVideo.durationSeconds > 0
                              ? Duration(seconds: currentVideo.durationSeconds)
                              : Duration.zero);

                      final maxSeconds = totalDuration.inSeconds > 0
                          ? totalDuration.inSeconds.toDouble()
                          : 1.0;
                      final currentSeconds =
                          position.inSeconds.toDouble().clamp(0.0, maxSeconds);

                      return Column(
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                              activeTrackColor: const Color(0xFF8B6BF0),
                              inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
                              thumbColor: Colors.white,
                              overlayColor: const Color(0x336C4CE0),
                            ),
                            child: Slider(
                              value: currentSeconds,
                              max: maxSeconds,
                              onChanged: (value) {
                                player.seek(Duration(seconds: value.toInt()));
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDuration(position),
                                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                                ),
                                Text(
                                  _formatDuration(totalDuration),
                                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                const SizedBox(height: 10),

                // ── Playback Controls (Shuffle, Prev, Play/Pause, Next, Repeat) ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Shuffle
                    IconButton(
                      icon: Icon(
                        Icons.shuffle_rounded,
                        color: player.isShuffled ? const Color(0xFF25D9A0) : AppTheme.textSecondary,
                        size: 24,
                      ),
                      onPressed: () => player.toggleShuffle(),
                    ),

                    // Previous
                    IconButton(
                      icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 38),
                      onPressed: () => player.playPrevious(),
                    ),

                    // Play/Pause Large Button
                    GestureDetector(
                      onTap: () => player.togglePlay(),
                      child: Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6C4CE0), Color(0xFF8B6BF0)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6C4CE0).withValues(alpha: 0.45),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Center(
                          child: (player.isLoadingAudio && !player.isPlaying)
                              ? const SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                                )
                              : Icon(
                                  player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 38,
                                ),
                        ),
                      ),
                    ),

                    // Next
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 38),
                      onPressed: () => player.playNext(),
                    ),

                    // Repeat
                    IconButton(
                      icon: Icon(
                        player.repeatMode == player_service_mode.RepeatMode.one
                            ? Icons.repeat_one_rounded
                            : Icons.repeat_rounded,
                        color: player.repeatMode != player_service_mode.RepeatMode.none
                            ? const Color(0xFF25D9A0)
                            : AppTheme.textSecondary,
                        size: 24,
                      ),
                      onPressed: () => player.cycleRepeatMode(),
                    ),
                  ],
                ),

                const Spacer(flex: 1),

                // ── Bottom Action Row (Add to Playlist & Queue) ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.playlist_add_rounded, color: AppTheme.textSecondary, size: 26),
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          backgroundColor: Colors.transparent,
                          isScrollControlled: true,
                          builder: (_) => AddToPlaylistSheet(video: currentVideo),
                        );
                      },
                    ),
                    TextButton.icon(
                      onPressed: () {
                        _showQueueSheet(context, player);
                      },
                      icon: const Icon(Icons.queue_music_rounded, color: AppTheme.textSecondary, size: 22),
                      label: Text(
                        'Antrean (${player.queue.length})',
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showQueueSheet(BuildContext context, PlayerService player) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161622),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Antrean Pemutaran',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: player.queue.length,
                  itemBuilder: (context, index) {
                    final item = player.queue[index];
                    final isCurrent = index == player.currentIndex;
                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: CachedNetworkImage(
                          imageUrl: item.thumbnailUrl,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                        ),
                      ),
                      title: Text(
                        item.title,
                        style: TextStyle(
                          color: isCurrent ? const Color(0xFF25D9A0) : Colors.white,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        item.channelTitle,
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        maxLines: 1,
                      ),
                      trailing: isCurrent
                          ? const Icon(Icons.volume_up_rounded, color: Color(0xFF25D9A0), size: 22)
                          : null,
                      onTap: () {
                        player.playAt(index);
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}



