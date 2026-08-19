// lib/screens/channel/channel_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';

import '../../models/channel_detail.dart';
import '../../models/video_item.dart';
import '../../services/youtube_service.dart';
import '../../providers/player_provider.dart';
import '../../theme/app_theme.dart';

class ChannelScreen extends ConsumerStatefulWidget {
  final String channelId;
  final String? initialTitle;

  const ChannelScreen({
    super.key,
    required this.channelId,
    this.initialTitle,
  });

  @override
  ConsumerState<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends ConsumerState<ChannelScreen> {
  ChannelDetail? _channel;
  List<VideoItem> _videos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final channel = await YoutubeService().getChannelDetail(widget.channelId);
      final videos = await YoutubeService().getChannelVideos(widget.channelId);
      if (mounted) {
        setState(() {
          _channel = channel;
          _videos = videos;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _channel?.title ?? widget.initialTitle ?? 'Artis';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryLight))
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 90),
              itemCount: _videos.length,
              itemBuilder: (context, index) {
                final video = _videos[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: video.thumbnailUrl,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                    ),
                  ),
                  title: Text(
                    video.title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    video.channelTitle,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.play_circle_outline_rounded, color: AppTheme.primaryLight, size: 28),
                  onTap: () {
                    ref.read(playerServiceProvider).playSingle(video);
                    context.push('/player', extra: video);
                  },
                );
              },
            ),
    );
  }
}
