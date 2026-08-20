// lib/services/permission_service.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static const _channel = MethodChannel('com.submarine/battery');

  static Future<void> requestBatteryAndNotificationPermissions(BuildContext context) async {
    // 1. Request Notification Permission (Android 13+)
    try {
      final notifStatus = await Permission.notification.status;
      if (!notifStatus.isGranted) {
        await Permission.notification.request();
      }
    } catch (_) {}

    // 2. Request Battery Exemption directly via native Android System Dialog
    try {
      final bool isOptimized = await _channel.invokeMethod('isBatteryOptimized') ?? false;
      if (isOptimized && context.mounted) {
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
                Text('Izin Latar Belakang', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: const Text(
              'Agar lagu tidak terhenti saat kamu menekan tombol Home atau mematikan layar HP (khususnya di HP Tecno/Infinix), pilih "Izinkan" / "Jangan Optimalkan".',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Nanti', style: TextStyle(color: Colors.white38)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  await _channel.invokeMethod('requestBatteryExemption');
                },
                child: const Text('Buka Pengaturan Izin'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('[PermissionService] Battery check error: $e');
    }
  }

  static Future<void> openBatterySettings() async {
    try {
      await _channel.invokeMethod('requestBatteryExemption');
    } catch (_) {}
  }
}
