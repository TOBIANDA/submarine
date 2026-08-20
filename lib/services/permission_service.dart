// lib/services/permission_service.dart
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static Future<void> requestBatteryAndNotificationPermissions(BuildContext context) async {
    // 1. Request Notification Permission (Android 13+)
    final notifStatus = await Permission.notification.status;
    if (!notifStatus.isGranted) {
      await Permission.notification.request();
    }

    // 2. Request Ignore Battery Optimizations
    final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
    if (!batteryStatus.isGranted) {
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.battery_charging_full_rounded, color: Color(0xFF8B5CF6)),
                SizedBox(width: 10),
                Text('Izin Putar Latar Belakang', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: const Text(
              'Agar musik tetap berputar lancar saat layar HP mati atau aplikasi diminimize (khususnya di HP Tecno/Infinix), izinkan Submarine berjalan tanpa batasan penghemat baterai.',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Nanti Saja', style: TextStyle(color: Colors.white38)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  await Permission.ignoreBatteryOptimizations.request();
                },
                child: const Text('Izinkan Sekarang'),
              ),
            ],
          ),
        );
      }
    }
  }
}
