// lib/services/stream_proxy_server.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Local Stream Proxy Server - Bypasses ExoPlayer 403 Forbidden by proxying
/// audio streams locally with the exact YouTube Android headers required.
class StreamProxyServer {
  static StreamProxyServer? _instance;
  StreamProxyServer._();
  factory StreamProxyServer() => _instance ??= StreamProxyServer._();

  HttpServer? _server;
  int get port => _server?.port ?? 0;

  static const String youtubeUserAgent =
      'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip';

  // Cache resolved stream URLs in memory (valid for ~6 hours)
  final Map<String, (String url, String mime)> _streamCache = {};

  Future<void> start() async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      debugPrint('[StreamProxy] Server started on port: $port');
      _server!.listen(_handleRequest);
    } catch (e) {
      debugPrint('[StreamProxy] Failed to start server: $e');
    }
  }

  String getStreamUrl(String videoId) {
    return 'http://127.0.0.1:$port/stream?id=$videoId';
  }

  Future<void> _handleRequest(HttpRequest req) async {
    final videoId = req.uri.queryParameters['id'];
    if (videoId == null || videoId.isEmpty) {
      req.response.statusCode = HttpStatus.badRequest;
      await req.response.close();
      return;
    }

    try {
      // 1. Get or resolve stream URL
      var cached = _streamCache[videoId];
      if (cached == null) {
        final resolved = await _resolveInnertubeStream(videoId);
        if (resolved == null) {
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
          return;
        }
        _streamCache[videoId] = resolved;
        cached = resolved;
      }

      final (streamUrl, mimeType) = cached;

      // 2. Fetch from GoogleVideo with required Android YouTube headers
      final client = HttpClient();
      final upstreamReq = await client.getUrl(Uri.parse(streamUrl));
      upstreamReq.headers.set('User-Agent', youtubeUserAgent);

      final range = req.headers.value('range');
      if (range != null) {
        upstreamReq.headers.set('Range', range);
      }

      final upstreamRes = await upstreamReq.close();
      req.response.statusCode = upstreamRes.statusCode;
      req.response.headers.contentType = ContentType.parse(mimeType);

      final clen = upstreamRes.headers.value('content-length');
      if (clen != null) {
        req.response.headers.set('Content-Length', clen);
      }

      final crange = upstreamRes.headers.value('content-range');
      if (crange != null) {
        req.response.headers.set('Content-Range', crange);
      }

      req.response.headers.set('Accept-Ranges', 'bytes');

      // Pipe data from GoogleVideo -> Local Proxy -> ExoPlayer
      await upstreamRes.pipe(req.response);
    } catch (e) {
      debugPrint('[StreamProxy] Request error for $videoId: $e');
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<(String, String)?> _resolveInnertubeStream(String videoId) async {
    final httpClient = http.Client();
    try {
      final resp = await httpClient.post(
        Uri.parse('https://www.youtube.com/youtubei/v1/player'),
        headers: {
          'User-Agent': youtubeUserAgent,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'context': {
            'client': {
              'clientName': 'ANDROID',
              'clientVersion': '20.10.38',
              'androidSdkVersion': 30,
              'userAgent': youtubeUserAgent,
              'hl': 'en',
              'gl': 'US',
            }
          },
          'videoId': videoId,
        }),
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final formats = (data['streamingData']?['adaptiveFormats'] as List?) ?? [];
        final audioStreams = formats.where((f) {
          final mime = f['mimeType'] as String? ?? '';
          return mime.startsWith('audio/') && f['url'] != null;
        }).toList();

        if (audioStreams.isNotEmpty) {
          audioStreams.sort((a, b) {
            final a140 = (a['itag'] == 140) ? 1 : 0;
            final b140 = (b['itag'] == 140) ? 1 : 0;
            if (a140 != b140) return b140.compareTo(a140);
            return ((b['bitrate'] as int?) ?? 0).compareTo((a['bitrate'] as int?) ?? 0);
          });

          final chosen = audioStreams.first;
          final rawUrl = chosen['url'] as String;
          final streamUrl = rawUrl.contains('?')
              ? '$rawUrl&rn=1&rbuf=0&ratebypass=yes'
              : '$rawUrl?rn=1&rbuf=0&ratebypass=yes';
          final mime = chosen['mimeType'] as String? ?? 'audio/mp4';
          return (streamUrl, mime);
        }
      }
    } catch (e) {
      debugPrint('[StreamProxy] Stream resolution error: $e');
    } finally {
      httpClient.close();
    }
    return null;
  }

  void dispose() {
    _server?.close(force: true);
    _server = null;
    _streamCache.clear();
  }
}
