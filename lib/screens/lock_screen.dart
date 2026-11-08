import 'dart:async';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../data/app_lock.dart';
import '../theme.dart';

/// Full-screen gate shown on cold start and after the resume timeout (F-54/55).
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  static const _accentInkOnButton = Color(0xFFFFF8F1);

  final LocalAuthentication _auth = LocalAuthentication();
  String _pin = '';
  String? _error;
  Timer? _ticker;
  bool _biometricBusy = false;
  bool _unlocked = false;

  @override
  void initState() {
    super.initState();
    _startLockoutTicker();
    if (AppLock.instance.biometricEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  bool get _lockedOut => AppLock.instance.isLockedOut;

  bool get _canSubmit => _pin.length >= 4 && !_lockedOut;

  void _startLockoutTicker() {
    _ticker?.cancel();
    if (!_lockedOut) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!_lockedOut) {
        _ticker?.cancel();
        setState(() => _error = null);
      } else {
        setState(() {});
      }
    });
  }

  void _append(String digit) {
    if (_lockedOut || _pin.length >= 6) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = null;
    });
  }

  void _submit() {
    if (!_canSubmit) return;
    if (AppLock.instance.verifyPin(_pin)) {
      _unlocked = true;
      widget.onUnlocked();
      return;
    }
    setState(() {
      _pin = '';
      _error = _lockedOut ? '错误次数过多，请稍后再试' : 'PIN 不正确，请重试';
    });
    _startLockoutTicker();
  }

  Future<void> _authenticate() async {
    if (_biometricBusy || _unlocked) return;
    setState(() => _biometricBusy = true);
    try {
      final ok = await _auth.authenticate(
        localizedReason: '解锁记问',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (ok && mounted && !_unlocked) {
        _unlocked = true;
        widget.onUnlocked();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = '生物识别不可用，请使用 PIN');
      }
    } finally {
      if (mounted) setState(() => _biometricBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lockedOut = _lockedOut;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: PopScope(
          canPop: false,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.lock_outline_rounded,
                      size: 28,
                      color: AppColors.accentInk,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '记问已锁定',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '输入 PIN 解锁',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var index = 0; index < 6; index++)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: index < _pin.length
                                  ? AppColors.accent
                                  : Colors.transparent,
                              border: Border.all(
                                color: index < _pin.length
                                    ? AppColors.accent
                                    : AppColors.line,
                                width: 1.2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 36,
                    child: Center(
                      child: Text(
                        lockedOut
                            ? '尝试次数过多，请 ${AppLock.instance.lockoutRemainingSeconds} 秒后再试'
                            : (_error ?? ''),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: lockedOut ? AppColors.danger : AppColors.muted,
                        ),
                      ),
                    ),
                  ),
                  _keyRow(['1', '2', '3']),
                  const SizedBox(height: 12),
                  _keyRow(['4', '5', '6']),
                  const SizedBox(height: 12),
                  _keyRow(['7', '8', '9']),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (AppLock.instance.biometricEnabled)
                        _key(
                          onTap: _biometricBusy ? null : _authenticate,
                          child: _biometricBusy
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.accent,
                                  ),
                                )
                              : Icon(
                                  Icons.fingerprint_rounded,
                                  size: 24,
                                  color: AppColors.accentInk,
                                ),
                        )
                      else
                        const SizedBox(width: 68, height: 54),
                      const SizedBox(width: 14),
                      _key(label: '0', onTap: () => _append('0')),
                      const SizedBox(width: 14),
                      _key(
                        onTap: _backspace,
                        child: Icon(
                          Icons.backspace_outlined,
                          size: 20,
                          color: AppColors.ink2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: 220,
                    height: 44,
                    child: FilledButton(
                      onPressed: _canSubmit ? _submit : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: _accentInkOnButton,
                        disabledBackgroundColor: AppColors.line,
                        disabledForegroundColor: AppColors.muted,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        lockedOut ? '已临时锁定' : '解锁',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    '忘记 PIN 无法找回，只能重装应用后导入备份恢复。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.6,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _keyRow(List<String> digits) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < digits.length; index++) ...[
          if (index > 0) const SizedBox(width: 14),
          _key(label: digits[index], onTap: () => _append(digits[index])),
        ],
      ],
    );
  }

  Widget _key({String? label, VoidCallback? onTap, Widget? child}) {
    return SizedBox(
      width: 68,
      height: 54,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child:
                child ??
                Text(
                  label ?? '',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink,
                  ),
                ),
          ),
        ),
      ),
    );
  }
}
