import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'notes_db.dart';

/// Auto-lock thresholds of F-55.
enum LockTimeout {
  immediate(0, '立即'),
  thirtySeconds(30, '30 秒'),
  oneMinute(60, '1 分钟'),
  fiveMinutes(300, '5 分钟'),
  never(-1, '从不');

  const LockTimeout(this.seconds, this.label);

  final int seconds;
  final String label;

  static LockTimeout fromStored(String? value) {
    final seconds = int.tryParse(value ?? '');
    for (final option in LockTimeout.values) {
      if (option.seconds == seconds) return option;
    }
    return LockTimeout.thirtySeconds;
  }

  /// Whether returning from a recorded background pause should lock.
  ///
  /// A missing pause means no real background transition happened, so there
  /// is nothing to measure; locking then would re-trigger on every dialog
  /// dismissal.
  bool shouldLockAfter(DateTime? pausedAt) {
    if (this == LockTimeout.never || pausedAt == null) return false;
    if (this == LockTimeout.immediate) return true;
    final elapsed = DateTime.now().difference(pausedAt).inSeconds;
    return elapsed >= seconds;
  }
}

/// PIN, biometric and timing settings for the app lock (F-54 ~ F-56).
class AppLock {
  AppLock._();

  static final AppLock instance = AppLock._();

  static const _keyEnabled = 'app_lock_enabled';
  static const _keyHash = 'app_lock_pin_hash';
  static const _keySalt = 'app_lock_pin_salt';
  static const _keyBiometric = 'app_lock_biometric';
  static const _keyTimeout = 'app_lock_timeout_sec';
  static const _keyBlockScreenshot = 'app_lock_block_screenshot';

  static final RegExp _pinPattern = RegExp(r'^\d{4,6}$');

  NotesDb get _db => NotesDb.instance;

  bool get enabled => _db.getSetting(_keyEnabled) == '1' && hasPin;

  bool get hasPin {
    final hash = _db.getSetting(_keyHash);
    final salt = _db.getSetting(_keySalt);
    return hash != null && hash.isNotEmpty && salt != null && salt.isNotEmpty;
  }

  bool get biometricEnabled => enabled && _db.getSetting(_keyBiometric) == '1';

  LockTimeout get timeout =>
      LockTimeout.fromStored(_db.getSetting(_keyTimeout));

  /// Defaults to on while the app lock is active.
  bool get blockScreenshot => _db.getSetting(_keyBlockScreenshot) != '0';

  static bool isValidPin(String pin) => _pinPattern.hasMatch(pin);

  /// Enables the lock with a freshly generated salt (F-54).
  void enableWithPin(String pin) {
    setPin(pin);
    _db.setSetting(_keyEnabled, '1');
    if (_db.getSetting(_keyTimeout) == null) {
      _db.setSetting(_keyTimeout, LockTimeout.thirtySeconds.seconds.toString());
    }
    if (_db.getSetting(_keyBlockScreenshot) == null) {
      _db.setSetting(_keyBlockScreenshot, '1');
    }
  }

  void setPin(String pin) {
    if (!isValidPin(pin)) {
      throw ArgumentError.value(pin, 'pin', 'PIN must be 4 to 6 digits');
    }
    final salt = _newSalt();
    _db.setSetting(_keySalt, salt);
    _db.setSetting(_keyHash, _hash(salt, pin));
  }

  void disable() {
    _db.setSetting(_keyEnabled, '0');
    _db.removeSetting(_keyHash);
    _db.removeSetting(_keySalt);
    _db.setSetting(_keyBiometric, '0');
    _failedAttempts = 0;
    _lockoutUntil = null;
  }

  void setBiometric(bool value) =>
      _db.setSetting(_keyBiometric, value ? '1' : '0');

  void setBlockScreenshot(bool value) {
    _db.setSetting(_keyBlockScreenshot, value ? '1' : '0');
  }

  void setTimeout(LockTimeout value) {
    _db.setSetting(_keyTimeout, value.seconds.toString());
  }

  int _failedAttempts = 0;
  DateTime? _lockoutUntil;

  /// Five wrong PINs lock the keypad for 30 seconds (F-56).
  bool get isLockedOut {
    final until = _lockoutUntil;
    if (until == null) return false;
    if (DateTime.now().isBefore(until)) return true;
    _lockoutUntil = null;
    _failedAttempts = 0;
    return false;
  }

  int get lockoutRemainingSeconds {
    if (!isLockedOut) return 0;
    return _lockoutUntil!.difference(DateTime.now()).inSeconds + 1;
  }

  bool verifyPin(String pin) {
    if (isLockedOut) return false;
    final salt = _db.getSetting(_keySalt);
    final stored = _db.getSetting(_keyHash);
    if (salt == null || stored == null) return false;
    if (_hash(salt, pin) == stored) {
      _failedAttempts = 0;
      return true;
    }
    _failedAttempts++;
    if (_failedAttempts >= 5) {
      _lockoutUntil = DateTime.now().add(const Duration(seconds: 30));
      _failedAttempts = 0;
    }
    return false;
  }

  static String _hash(String salt, String pin) {
    return sha256.convert(utf8.encode('$salt:$pin')).toString();
  }

  static String _newSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }
}
