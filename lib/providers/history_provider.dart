// lib/providers/history_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/play_history.dart';
import '../services/db_service.dart';

final historyProvider = FutureProvider<List<PlayHistory>>((ref) async {
  return DbService().getPlayHistory(limit: 30);
});

final lastPlayedProvider = FutureProvider<PlayHistory?>((ref) async {
  return DbService().getLastPlayed();
});
