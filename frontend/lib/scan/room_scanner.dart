import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridge to the native ARCore room scanner (android/.../ScanActivity.kt).
class RoomScanner {
  static const _ch = MethodChannel('hometwin/room_scan');

  /// Room scan works on Android only (ARCore).
  static bool get platformOk => !kIsWeb && Platform.isAndroid;

  /// 'supported' | 'needs_install' | 'unsupported'
  static Future<String> availability() async {
    for (var i = 0; i < 4; i++) {
      final r = await _ch.invokeMethod<String>('isSupported') ?? 'unsupported';
      if (r != 'checking') return r;
      await Future.delayed(const Duration(milliseconds: 400));
    }
    return 'supported'; // ARCore is still checking; the scan screen handles it
  }

  /// Opens the AR scanner. Returns the scan JSON, or null if the user cancelled.
  /// Throws [PlatformException] (code 'scan_failed') with a user-readable message.
  static Future<Map<String, dynamic>?> scan() async {
    final s = await _ch.invokeMethod<String>('startScan');
    if (s == null) return null;
    return Map<String, dynamic>.from(jsonDecode(s));
  }
}