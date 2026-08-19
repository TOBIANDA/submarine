// lib/models/channel_detail.dart

class ChannelDetail {
  final String id;
  final String title;
  final String? logoUrl;
  final String? bannerUrl;
  final String subscribersCount;
  final String description;
  final int videoCount;

  ChannelDetail({
    required this.id,
    required this.title,
    this.logoUrl,
    this.bannerUrl,
    this.subscribersCount = '0 subscriber',
    this.description = '',
    this.videoCount = 0,
  });
}
