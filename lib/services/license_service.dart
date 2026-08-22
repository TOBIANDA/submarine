// lib/services/license_service.dart
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class LicenseVerificationResult {
  final bool isValid;
  final bool isActive;
  final String? userName;
  final String? code;
  final String? errorMessage;

  LicenseVerificationResult({
    required this.isValid,
    required this.isActive,
    this.userName,
    this.code,
    this.errorMessage,
  });
}

class LicenseService {
  static LicenseService? _instance;
  LicenseService._();
  factory LicenseService() => _instance ??= LicenseService._();

  // Flag compile-time: Jika dibuild dengan --dart-define=VIP_BUILD=true maka bebas kunci selamanya
  static const bool isVipBuild = bool.fromEnvironment('VIP_BUILD', defaultValue: false);

  // Cloudflare License Endpoint
  static const String licenseEndpoint = 'https://submarine-keys.workers.dev/api/verify';

  // Master VIP keys yang selalu valid secara offline
  static const Set<String> _offlineMasterKeys = {
    'SUB-VIP-MASTER',
    'SUB-TOBIANDA-VIP',
    'SUB-DEV-2026',
    'SUBMARINE-VIP-KEY',
  };

  static const String _prefKeyActivated = 'sub_license_activated';
  static const String _prefKeyCode = 'sub_license_code';
  static const String _prefKeyName = 'sub_license_name';
  static const String _prefKeyDeviceId = 'sub_device_id';

  /// Dapatkan atau buat Device ID unik untuk HP ini
  Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? devId = prefs.getString(_prefKeyDeviceId);
    if (devId == null || devId.isEmpty) {
      final rand = Random().nextInt(999999).toString().padLeft(6, '0');
      devId = 'DEV-${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}-$rand';
      await prefs.setString(_prefKeyDeviceId, devId);
    }
    return devId;
  }

  /// Cek apakah aplikasi saat ini dalam status teraktivasi
  Future<bool> isActivated() async {
    if (isVipBuild) return true;

    final prefs = await SharedPreferences.getInstance();
    final isAct = prefs.getBool(_prefKeyActivated) ?? false;
    final code = prefs.getString(_prefKeyCode);

    if (!isAct || code == null || code.isEmpty) {
      return false;
    }

    return true;
  }

  /// Ambil nama pemegang lisensi saat ini
  Future<String> getLicenseHolderName() async {
    if (isVipBuild) return 'VIP Master Account';
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKeyName) ?? 'Pengguna Submarine';
  }

  /// Ambil kode lisensi saat ini
  Future<String?> getActiveLicenseCode() async {
    if (isVipBuild) return 'VIP-UNLIMITED';
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKeyCode);
  }

  /// Verifikasi kode akses baru dengan Device-Lock
  Future<LicenseVerificationResult> verifyAndActivate(String rawCode) async {
    final code = rawCode.trim().toUpperCase().replaceAll(' ', '');
    if (code.isEmpty) {
      return LicenseVerificationResult(
        isValid: false,
        isActive: false,
        errorMessage: 'Kode akses tidak boleh kosong.',
      );
    }

    final deviceId = await getOrCreateDeviceId();

    // 1. Cek Offline Master Keys
    if (_offlineMasterKeys.contains(code)) {
      await _saveActivation(code, 'VIP Special Member');
      return LicenseVerificationResult(
        isValid: true,
        isActive: true,
        userName: 'VIP Special Member',
        code: code,
      );
    }

    // 2. Cek Cloudflare Worker Backend API dengan Device-Lock
    try {
      final uri = Uri.parse('$licenseEndpoint?code=${Uri.encodeComponent(code)}&deviceId=${Uri.encodeComponent(deviceId)}');
      final response = await http.get(uri).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final name = data['name']?.toString() ?? 'Pengguna Submarine';
        await _saveActivation(code, name);

        return LicenseVerificationResult(
          isValid: true,
          isActive: true,
          userName: name,
          code: code,
        );
      } else if (response.statusCode == 403) {
        final data = jsonDecode(response.body);
        return LicenseVerificationResult(
          isValid: true,
          isActive: false,
          errorMessage: data['error']?.toString() ?? 'Kunci ini sudah terpakai di perangkat lain atau dicabut oleh admin.',
        );
      } else if (response.statusCode == 404) {
        return LicenseVerificationResult(
          isValid: false,
          isActive: false,
          errorMessage: 'Kode kunci tidak terdaftar. Hubungi Tobi untuk mendapatkan akses.',
        );
      }
    } catch (e) {
      debugPrint('[License] Cloud check error: $e');
    }

    // 3. Fallback jika offline pertama kali
    if (code.startsWith('SUB-') && code.length >= 8) {
      final parts = code.split('-');
      final name = parts.length > 1 ? parts[1] : 'Pengguna';
      await _saveActivation(code, name);
      return LicenseVerificationResult(
        isValid: true,
        isActive: true,
        userName: name,
        code: code,
      );
    }

    return LicenseVerificationResult(
      isValid: false,
      isActive: false,
      errorMessage: 'Kode akses tidak valid. Pastikan format benar (contoh: SUB-ANDI-9281).',
    );
  }

  /// Sinkronisasi berkala (misal cek apakah admin mencabut izin di background)
  Future<bool> checkRevokeStatusInBackground() async {
    if (isVipBuild) return true;

    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefKeyCode);
    if (code == null || code.isEmpty) return false;

    if (_offlineMasterKeys.contains(code)) return true;

    try {
      final deviceId = await getOrCreateDeviceId();
      final uri = Uri.parse('$licenseEndpoint?code=${Uri.encodeComponent(code)}&deviceId=${Uri.encodeComponent(deviceId)}');
      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 403) {
        // Dicabut atau device tidak cocok!
        await revokeLocally();
        return false;
      }
    } catch (_) {}

    return true;
  }

  Future<void> _saveActivation(String code, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyActivated, true);
    await prefs.setString(_prefKeyCode, code);
    await prefs.setString(_prefKeyName, name);
  }

  Future<void> revokeLocally() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyActivated, false);
  }
}
