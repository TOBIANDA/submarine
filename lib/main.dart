import 'services/download_service.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'providers/player_provider.dart';
import 'router.dart';
import 'services/audio_handler.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  DownloadService().init();

  // Init FlutterDownloader - wrapped in try/catch agar tidak crash jika gagal
  try {
    await FlutterDownloader.initialize(debug: false, ignoreSsl: true);
  } catch (e) {
    debugPrint('[Submarine] FlutterDownloader init gagal: $e');
  }

  // Request permissions - semua dibungkus try/catch
  try {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  } catch (_) {}

  try {
    await Permission.storage.request();
  } catch (_) {}

  try {
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  } catch (_) {}

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppTheme.surface,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Init AudioService - crash-safe dengan 2 level fallback
  BackgroundAudioHandler? audioHandler;
  final channelIds = [
    'com.example.streamly.audio.channel',
    'com.submarine.audio.v2',
    'submarine.audio.fallback',
  ];

  for (final channelId in channelIds) {
    try {
      audioHandler = await AudioService.init(
        builder: () => BackgroundAudioHandler(),
        config: AudioServiceConfig(
          androidNotificationChannelId: channelId,
          androidNotificationChannelName: 'Submarine Audio',
          androidNotificationOngoing: false,
          androidStopForegroundOnPause: false,
          androidNotificationIcon: 'mipmap/ic_launcher',
          androidShowNotificationBadge: true,
          notificationColor: const Color(0xFF7B2FBE),
        ),
      );
      debugPrint('[Submarine] AudioService berhasil dengan channel: $channelId');
      break; // Berhasil, hentikan loop
    } catch (e) {
      debugPrint('[Submarine] Channel $channelId gagal: $e');
      continue;
    }
  }

  // Jika semua channel gagal, buat handler tanpa AudioService
  audioHandler ??= BackgroundAudioHandler();

  runApp(
    ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(audioHandler),
      ],
      child: const SubmarineApp(),
    ),
  );
}

// Global key untuk SnackBar dari Provider/Service
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

class SubmarineApp extends StatelessWidget {
  const SubmarineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Submarine',
      theme: AppTheme.theme,
      routerConfig: goRouter,
      scaffoldMessengerKey: scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
    );
  }
}
