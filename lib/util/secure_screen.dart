import 'dart:io';

import 'package:flutter/services.dart';

import '../data/app_lock.dart';

/// Blocks screenshots and the recent-tasks thumbnail while the app lock is
/// enabled and the hardening switch is on (F-56).
class SecureScreen {
  static const MethodChannel _channel = MethodChannel(
    'com.musen.jiwen/security',
  );

  static Future<void> apply() async {
    if (!Platform.isAndroid) return;
    final enabled =
        AppLock.instance.enabled && AppLock.instance.blockScreenshot;
    try {
      await _channel.invokeMethod<void>('setSecure', enabled);
    } catch (_) {
      // The setting must never crash the app on an unsupported platform.
    }
  }
}
