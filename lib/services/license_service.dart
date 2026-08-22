// lib/services/license_service.dart
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
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

  static const bool isVipBuild = bool.fromEnvironment('VIP_BUILD', defaultValue: false);

  // Cloudflare License Endpoint
  static const String licenseEndpoint = 'https://submarinekey.kuahsayurgaming9.workers.dev/api/verify';

  // Obfuscated Salt for Cryptographic Signature
  static String get _signatureSalt {
    final saltBytes = [83, 117, 98, 77, 97, 114, 105, 110, 101, 95, 83, 101, 99, 117, 114, 101, 95, 50, 48, 50, 54, 95, 83, 97, 108, 116];
    return String.fromCharCodes(saltBytes);
  }

  static const String _prefKeySignature = 'sub_license_sig';
  static const String _prefKeyCode = 'sub_license_code';
  static const String _prefKeyName = 'sub_license_name';
  static const String _prefKeyDeviceId = 'sub_device_id';

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

  String _generateSignature(String deviceId, String code) {
    final raw = '$deviceId:$code:$_signatureSalt';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  bool _validateChecksum(String code) {
    final clean = code.trim().toUpperCase().replaceAll(' ', '');
    final parts = clean.split('-');
    if (parts.length != 3 || parts[0] != 'SUB') return false;

    final name = parts[1];
    final providedHash = parts[2];

    final raw = '$name:$_signatureSalt';
    final expectedHash = sha256.convert(utf8.encode(raw)).toString().toUpperCase().substring(0, 6);

    return providedHash == expectedHash;
  }

  String _extractNameFromCode(String code) {
    final clean = code.trim().toUpperCase().replaceAll(' ', '');
    final parts = clean.split('-');
    if (parts.length >= 2 && parts[0] == 'SUB') {
      return parts[1];
    }
    return 'Pengguna Submarine';
  }

  Future<bool> isActivated() async {
    if (isVipBuild) return true;

    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefKeyCode);
    final storedSig = prefs.getString(_prefKeySignature);
    final deviceId = prefs.getString(_prefKeyDeviceId);

    if (code == null || code.isEmpty || storedSig == null || storedSig.isEmpty || deviceId == null || deviceId.isEmpty) {
      return false;
    }

    final expectedSig = _generateSignature(deviceId, code);
    if (storedSig != expectedSig) {
      debugPrint('[Security] Digital signature mismatch! Locking app.');
      await revokeLocally();
      return false;
    }

    return true;
  }

  Future<String> getLicenseHolderName() async {
    if (isVipBuild) return 'VIP Master Account';
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKeyName) ?? 'Pengguna Submarine';
  }

  Future<String?> getActiveLicenseCode() async {
    if (isVipBuild) return 'VIP-UNLIMITED';
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKeyCode);
  }

  /// Verifikasi kode akses: Cek Cloudflare Server & Kriptografi
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

    // 1. Cek langsung ke Cloudflare Server (Mendukung custom code apa saja dari Dashboard)
    try {
      final uri = Uri.parse('$licenseEndpoint?code=${Uri.encodeComponent(code)}&deviceId=${Uri.encodeComponent(deviceId)}');
      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final name = data['name']?.toString() ?? _extractNameFromCode(code);
        await _saveActivationWithSignature(deviceId, code, name);

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
          errorMessage: data['error']?.toString() ?? 'Kunci ini telah dicabut oleh admin.',
        );
      }
    } catch (e) {
      debugPrint('[License] Cloud API check: $e');
    }

    // 2. Cek Kriptografi Checksum Offline
    if (_validateChecksum(code)) {
      final userName = _extractNameFromCode(code);
      await _saveActivationWithSignature(deviceId, code, userName);

      return LicenseVerificationResult(
        isValid: true,
        isActive: true,
        userName: userName,
        code: code,
      );
    }

    // 3. Cek Default VIP Master Code
    if (code == 'SUB-VIP' || code == 'SUB-VIP-MASTER') {
      await _saveActivationWithSignature(deviceId, code, 'VIP Member');
      return LicenseVerificationResult(
        isValid: true,
        isActive: true,
        userName: 'VIP Member',
        code: code,
      );
    }

    return LicenseVerificationResult(
      isValid: false,
      isActive: false,
      errorMessage: 'Kode akses salah. Masukkan kode resmi dari Dashboard Admin (contoh: SUB-ANDI-958D09 atau SUB-VIP).',
    );
  }

  Future<bool> checkRevokeStatusInBackground() async {
    if (isVipBuild) return true;

    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefKeyCode);
    final storedSig = prefs.getString(_prefKeySignature);
    final deviceId = prefs.getString(_prefKeyDeviceId);

    if (code == null || code.isEmpty || storedSig == null || deviceId == null) {
      return false;
    }

    if (storedSig != _generateSignature(deviceId, code)) {
      await revokeLocally();
      return false;
    }

    try {
      final uri = Uri.parse('$licenseEndpoint?code=${Uri.encodeComponent(code)}&deviceId=${Uri.encodeComponent(deviceId)}');
      final response = await http.get(uri).timeout(const Duration(seconds: 4));

      if (response.statusCode == 403 || response.statusCode == 404) {
        await revokeLocally();
        return false;
      }
    } catch (_) {}

    return true;
  }

  Future<void> _saveActivationWithSignature(String deviceId, String code, String name) async {
    final sig = _generateSignature(deviceId, code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeySignature, sig);
    await prefs.setString(_prefKeyCode, code);
    await prefs.setString(_prefKeyName, name);
  }

  Future<void> revokeLocally() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeySignature);
    await prefs.remove(_prefKeyCode);
  }
}
