// lib/services/db_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../models/video_item.dart';
import '../models/playlist.dart';
import '../models/play_history.dart';
import '../models/downloaded_track.dart';
import '../core/app_constants.dart';

class DbService {
  static DbService? _instance;
  static Database? _db;

  DbService._();
  factory DbService() => _instance ??= DbService._();

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), AppConstants.dbName);
    return openDatabase(
      path,
      version: AppConstants.dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE playlists (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        source TEXT NOT NULL DEFAULT 'manual'
      )
    ''');

    await db.execute('''
      CREATE TABLE playlist_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        playlistId TEXT NOT NULL,
        videoId TEXT NOT NULL,
        title TEXT NOT NULL,
        channelTitle TEXT NOT NULL,
        thumbnailUrl TEXT NOT NULL,
        durationSeconds INTEGER NOT NULL DEFAULT 0,
        `order` INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (playlistId) REFERENCES playlists(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE play_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        videoId TEXT NOT NULL,
        title TEXT NOT NULL,
        channelTitle TEXT NOT NULL,
        thumbnailUrl TEXT NOT NULL,
        durationSeconds INTEGER NOT NULL DEFAULT 0,
        playedAt TEXT NOT NULL,
        lastPositionSeconds INTEGER NOT NULL DEFAULT 0,
        completionRate REAL NOT NULL DEFAULT 1.0,
        playlistId TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE downloads (
        videoId TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        channelTitle TEXT NOT NULL,
        thumbnailUrl TEXT NOT NULL,
        durationSeconds INTEGER NOT NULL DEFAULT 0,
        localPath TEXT NOT NULL,
        downloadedAt TEXT NOT NULL,
        fileSizeBytes INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE active_downloads (
        taskId TEXT PRIMARY KEY,
        videoId TEXT NOT NULL,
        title TEXT NOT NULL,
        channelTitle TEXT NOT NULL,
        thumbnailUrl TEXT NOT NULL,
        durationSeconds INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE recommendation_cache (
        key TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        cachedAt INTEGER NOT NULL,
        ttlSeconds INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS downloads (
          videoId TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          channelTitle TEXT NOT NULL,
          thumbnailUrl TEXT NOT NULL,
          durationSeconds INTEGER NOT NULL DEFAULT 0,
          localPath TEXT NOT NULL,
          downloadedAt TEXT NOT NULL,
          fileSizeBytes INTEGER NOT NULL DEFAULT 0
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS active_downloads (
          taskId TEXT PRIMARY KEY,
          videoId TEXT NOT NULL,
          title TEXT NOT NULL,
          channelTitle TEXT NOT NULL,
          thumbnailUrl TEXT NOT NULL,
          durationSeconds INTEGER NOT NULL DEFAULT 0
        )
      ''');
    }
    if (oldVersion < 4) {
      try {
        await db.execute('ALTER TABLE play_history ADD COLUMN completionRate REAL NOT NULL DEFAULT 1.0');
      } catch (_) {}

      await db.execute('''
        CREATE TABLE IF NOT EXISTS recommendation_cache (
          key TEXT PRIMARY KEY,
          data TEXT NOT NULL,
          cachedAt INTEGER NOT NULL,
          ttlSeconds INTEGER NOT NULL
        )
      ''');
    }
  }

  // ── Playlists ─────────────────────────────────────────────────────────────

  Future<List<Playlist>> getAllPlaylists() => getPlaylists();

  Future<List<Playlist>> getPlaylists() async {
    final db = await database;
    final rows = await db.query('playlists', orderBy: 'createdAt DESC');
    return rows.map(Playlist.fromMap).toList();
  }

  Future<Playlist?> getPlaylist(String id) async {
    final db = await database;
    final rows =
        await db.query('playlists', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final playlist = Playlist.fromMap(rows.first);
    final items = await getPlaylistItems(id);
    return playlist.copyWith(items: items);
  }

  Future<void> insertPlaylist(Playlist playlist) async {
    final db = await database;
    await db.insert(
      'playlists',
      {
        'id': playlist.id,
        'title': playlist.title,
        'createdAt': playlist.createdAt.toIso8601String(),
        'source': playlist.source,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    for (int i = 0; i < playlist.items.length; i++) {
      final item = playlist.items[i];
      item.order = i;
      await _insertPlaylistItem(db, playlist.id, item);
    }
  }

  Future<void> updatePlaylistTitle(String id, String title) async {
    final db = await database;
    await db.update('playlists', {'title': title},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deletePlaylist(String id) async {
    final db = await database;
    await db.delete('playlists', where: 'id = ?', whereArgs: [id]);
    await db.delete('playlist_items', where: 'playlistId = ?', whereArgs: [id]);
  }

  // ── Playlist Items ────────────────────────────────────────────────────────

  Future<List<VideoItem>> getPlaylistItems(String playlistId) async {
    final db = await database;
    final rows = await db.query(
      'playlist_items',
      where: 'playlistId = ?',
      whereArgs: [playlistId],
      orderBy: '`order` ASC',
    );
    return rows.map(VideoItem.fromMap).toList();
  }

  Future<void> addItemToPlaylist(String playlistId, VideoItem item) async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT MAX(`order`) as maxOrder FROM playlist_items WHERE playlistId = ?',
        [playlistId]);
    final maxOrder = (result.first['maxOrder'] as int?) ?? -1;
    item.order = maxOrder + 1;
    await _insertPlaylistItem(db, playlistId, item);
  }

  Future<void> removeItemFromPlaylist(String playlistId, String videoId) async {
    final db = await database;
    await db.delete(
      'playlist_items',
      where: 'playlistId = ? AND videoId = ?',
      whereArgs: [playlistId, videoId],
    );
  }

  Future<void> reorderPlaylistItems(
      String playlistId, List<VideoItem> items) async {
    final db = await database;
    await db.delete('playlist_items',
        where: 'playlistId = ?', whereArgs: [playlistId]);
    for (int i = 0; i < items.length; i++) {
      items[i].order = i;
      await _insertPlaylistItem(db, playlistId, items[i]);
    }
  }

  Future<void> _insertPlaylistItem(
      Database db, String playlistId, VideoItem item) async {
    await db.insert(
      'playlist_items',
      {
        'playlistId': playlistId,
        'videoId': item.videoId,
        'title': item.title,
        'channelTitle': item.channelTitle,
        'thumbnailUrl': item.thumbnailUrl,
        'durationSeconds': item.durationSeconds,
        'order': item.order,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ── Active Downloads (Background Tracking) ────────────────────────────────
  
  Future<void> insertActiveDownload(String taskId, VideoItem video) async {
    final db = await database;
    await db.insert(
      'active_downloads',
      {
        'taskId': taskId,
        'videoId': video.videoId,
        'title': video.title,
        'channelTitle': video.channelTitle,
        'thumbnailUrl': video.thumbnailUrl,
        'durationSeconds': video.durationSeconds,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<VideoItem?> getActiveDownload(String taskId) async {
    final db = await database;
    final maps = await db.query(
      'active_downloads',
      where: 'taskId = ?',
      whereArgs: [taskId],
    );
    if (maps.isNotEmpty) {
      final map = maps.first;
      return VideoItem(
        videoId: map['videoId'] as String,
        title: map['title'] as String,
        channelTitle: map['channelTitle'] as String,
        thumbnailUrl: map['thumbnailUrl'] as String,
        durationSeconds: map['durationSeconds'] as int,
      );
    }
    return null;
  }

  Future<void> removeActiveDownload(String taskId) async {
    final db = await database;
    await db.delete(
      'active_downloads',
      where: 'taskId = ?',
      whereArgs: [taskId],
    );
  }

  // ── Play History & Taste Profiling ────────────────────────────────────────

  Future<List<PlayHistory>> getPlayHistory({int limit = 50}) async {
    final db = await database;
    final rows = await db.query(
      'play_history',
      orderBy: 'playedAt DESC',
      limit: limit,
    );
    return rows.map(PlayHistory.fromMap).toList();
  }

  Future<PlayHistory?> getLastPlayed() async {
    final db = await database;
    final rows = await db.query('play_history',
        orderBy: 'playedAt DESC', limit: 1);
    if (rows.isEmpty) return null;
    return PlayHistory.fromMap(rows.first);
  }

  Future<void> upsertHistory(PlayHistory history) async {
    final db = await database;
    final existing = await db.query(
      'play_history',
      where: 'videoId = ?',
      whereArgs: [history.videoId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      await db.update(
        'play_history',
        {
          'playedAt': DateTime.now().toIso8601String(),
          'lastPositionSeconds': history.lastPositionSeconds,
          'completionRate': history.completionRate,
        },
        where: 'videoId = ?',
        whereArgs: [history.videoId],
      );
    } else {
      await db.insert('play_history', history.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> updatePlaybackCompletion(String videoId, double completionRate, int lastPos) async {
    final db = await database;
    await db.update(
      'play_history',
      {
        'completionRate': completionRate.clamp(0.0, 1.0),
        'lastPositionSeconds': lastPos,
      },
      where: 'videoId = ?',
      whereArgs: [videoId],
    );
  }

  /// Taste Query: Ambil artis yang paling sering didengarkan secara tuntas dalam 30 hari terakhir
  Future<List<String>> getTopTasteArtists({int limit = 5}) async {
    final db = await database;
    try {
      final rows = await db.rawQuery('''
        SELECT 
          channelTitle,
          COUNT(*) as playCount,
          AVG(completionRate) as avgCompletion
        FROM play_history 
        WHERE channelTitle != '' AND channelTitle IS NOT NULL
        GROUP BY channelTitle
        ORDER BY (COUNT(*) * AVG(completionRate)) DESC
        LIMIT ?
      ''', [limit]);

      return rows.map((r) => r['channelTitle'] as String).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> clearHistory() async {
    final db = await database;
    await db.delete('play_history');
  }

  // ── Recommendation Cache (12h - 24h TTL) ──────────────────────────────────

  Future<List<VideoItem>?> getCachedRecommendations(String key) async {
    final db = await database;
    try {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final rows = await db.query(
        'recommendation_cache',
        where: 'key = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final cachedAt = rows.first['cachedAt'] as int;
        final ttl = rows.first['ttlSeconds'] as int;
        if (now - cachedAt < ttl) {
          final jsonStr = rows.first['data'] as String;
          final List decoded = jsonDecode(jsonStr);
          return decoded.map((item) => VideoItem.fromMap(item as Map<String, dynamic>)).toList();
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> setCachedRecommendations(String key, List<VideoItem> items, {int ttlHours = 24}) async {
    final db = await database;
    try {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final jsonStr = jsonEncode(items.map((e) => e.toMap()).toList());
      await db.insert(
        'recommendation_cache',
        {
          'key': key,
          'data': jsonStr,
          'cachedAt': now,
          'ttlSeconds': ttlHours * 3600,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  // ── Downloads ─────────────────────────────────────────────────────────────

  Future<void> insertDownload(DownloadedTrack track) async {
    final db = await database;
    await db.insert('downloads', track.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<DownloadedTrack>> getAllDownloads() async {
    final db = await database;
    final rows = await db.query('downloads', orderBy: 'downloadedAt DESC');
    return rows.map(DownloadedTrack.fromMap).toList();
  }

  Future<DownloadedTrack?> getDownload(String videoId) async {
    final db = await database;
    final rows = await db.query('downloads',
        where: 'videoId = ?', whereArgs: [videoId], limit: 1);
    if (rows.isEmpty) return null;
    return DownloadedTrack.fromMap(rows.first);
  }

  Future<bool> isDownloaded(String videoId) async {
    final db = await database;
    final rows = await db.query('downloads',
        columns: ['videoId'],
        where: 'videoId = ?',
        whereArgs: [videoId],
        limit: 1);
    return rows.isNotEmpty;
  }

  Future<void> deleteDownload(String videoId) async {
    final db = await database;
    await db.delete('downloads', where: 'videoId = ?', whereArgs: [videoId]);
  }

  // ── Favorites ─────────────────────────────────────────────────────────────

  Future<bool> isFavorite(String videoId) async {
    final db = await database;
    final rows = await db.query(
      'playlist_items',
      where: 'playlistId = ? AND videoId = ?',
      whereArgs: ['favorites', videoId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<bool> toggleFavorite(VideoItem video) async {
    final db = await database;
    await db.insert(
      'playlists',
      {
        'id': 'favorites',
        'title': 'Lagu Favorit',
        'createdAt': DateTime.now().toIso8601String(),
        'source': 'favorites',
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    final isFav = await isFavorite(video.videoId);
    if (isFav) {
      await removeItemFromPlaylist('favorites', video.videoId);
      return false;
    } else {
      await addItemToPlaylist('favorites', video);
      return true;
    }
  }
}
