import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../data/app_lock.dart';
import '../data/app_settings.dart';
import '../theme.dart';
import '../util/secure_screen.dart';
import '../widgets/note_action_sheet.dart';
import 'data_tools_screen.dart';
import 'statistics_screen.dart';

/// Appearance and behaviour options (F-46 ~ F-49).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AppSettings get _settings => AppSettings.instance;

  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    try {
      final auth = LocalAuthentication();
      final supported = await auth.isDeviceSupported();
      final enrolled = await auth.canCheckBiometrics;
      if (mounted) {
        setState(() => _biometricAvailable = supported && enrolled);
      }
    } catch (_) {
      // Devices without biometric hardware simply keep the switch hidden.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
          color: AppColors.ink,
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: Text(
          '设置',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          _section('外观'),
          _choiceTile(
            title: '深色模式',
            value: _settings.themeMode.label,
            subtitle: '跟随系统或固定使用浅色 / 深色',
            onTap: _pickThemeMode,
          ),
          _choiceTile(
            title: '字体',
            value: _settings.fontFamily.label,
            subtitle: '系统默认，或内置宋体',
            onTap: _pickFontFamily,
          ),
          _choiceTile(
            title: '正文字号',
            value: _settings.fontSize.label,
            subtitle: '列表摘要与详情正文同时生效',
            onTap: _pickFontSize,
          ),
          _choiceTile(
            title: '列表密度',
            value: _settings.listDensity.label,
            subtitle: '紧凑一屏约 8~9 条，宽松摘要显示 3 行',
            onTap: _pickListDensity,
          ),
          _section('首页'),
          _choiceTile(
            title: '默认视图',
            value: _settings.homeView.label,
            subtitle: '下次打开应用时进入的列表视图',
            onTap: _pickHomeView,
          ),
          _switchTile(
            title: '打开应用直接进入新建',
            subtitle: '跳过首页，打开即光标就绪',
            value: _settings.openToNewNote,
            onChanged: (value) {
              _settings.setOpenToNewNote(value);
              setState(() {});
            },
          ),
          _section('安全'),
          _switchTile(
            title: '应用锁',
            subtitle: '冷启动或从后台返回时验证 PIN',
            value: AppLock.instance.enabled,
            onChanged: _toggleAppLock,
          ),
          if (AppLock.instance.enabled) ...[
            _actionTile(
              icon: Icons.pin_rounded,
              title: '修改 PIN',
              subtitle: '当前 PIN 不会被保存为明文',
              onTap: _changePin,
            ),
            _switchTile(
              title: '生物识别解锁',
              subtitle: _biometricAvailable
                  ? '指纹 / 面容快捷解锁，失败自动回退 PIN'
                  : '当前设备没有可用的生物识别',
              value: AppLock.instance.biometricEnabled,
              onChanged: _biometricAvailable ? _toggleBiometric : null,
            ),
            _choiceTile(
              title: '自动锁定',
              value: AppLock.instance.timeout.label,
              subtitle: '从后台返回超过该时长后需要重新解锁',
              onTap: _pickLockTimeout,
            ),
            _switchTile(
              title: '禁止截屏与最近任务缩略图',
              subtitle: '开启后系统截屏与多任务预览均被阻止',
              value: AppLock.instance.blockScreenshot,
              onChanged: _toggleSecure,
            ),
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '忘记 PIN 无法找回，只能重装应用后从备份导入恢复。PIN 仅以加盐哈希形式保存在本机。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.7,
                  color: AppColors.accentInk,
                ),
              ),
            ),
          ],
          _section('数据'),
          _actionTile(
            icon: Icons.bar_chart_rounded,
            title: '统计',
            subtitle: '笔记总数、待解答与标签分布',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StatisticsScreen()),
            ),
          ),
          _actionTile(
            icon: Icons.storage_rounded,
            title: '数据与备份',
            subtitle: '导出、导入与本地备份',
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const DataToolsScreen())),
          ),
          _section('说明'),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '所有数据只保存在本机应用私有目录，卸载应用会全部清除。本应用不会发起任何网络请求。',
              style: TextStyle(
                fontSize: 12,
                height: 1.7,
                color: AppColors.accentInk,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickThemeMode() async {
    final picked = await _pickOption<AppThemeChoice>(
      title: '深色模式',
      values: AppThemeChoice.values,
      current: _settings.themeMode,
      labelOf: (value) => value.label,
    );
    if (picked == null || !mounted) return;
    _settings.setThemeMode(picked);
    setState(() {});
  }

  Future<void> _pickListDensity() async {
    final picked = await _pickOption<AppListDensity>(
      title: '列表密度',
      values: AppListDensity.values,
      current: _settings.listDensity,
      labelOf: (value) => '${value.label} · 摘要 ${value.excerptLines} 行',
    );
    if (picked == null || !mounted) return;
    _settings.setListDensity(picked);
    setState(() {});
  }

  Future<void> _pickFontFamily() async {
    final picked = await showModalBottomSheet<AppFontFamily>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '字体',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ),
              for (final family in AppFontFamily.values)
                ListTile(
                  title: Text(
                    '${family.label} · 正文示例',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      fontFamily: family.family,
                      color: AppColors.ink2,
                    ),
                  ),
                  trailing: family == _settings.fontFamily
                      ? Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: AppColors.accent,
                        )
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(family),
                ),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    _settings.setFontFamily(picked);
    setState(() {});
  }

  Future<void> _pickFontSize() async {
    final picked = await showModalBottomSheet<AppFontSize>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '正文字号',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ),
              for (final size in AppFontSize.values)
                ListTile(
                  title: Text(
                    '${size.label} · 正文示例',
                    style: TextStyle(
                      fontSize: 14 * size.scale,
                      height: 1.6,
                      color: AppColors.ink2,
                    ),
                  ),
                  trailing: size == _settings.fontSize
                      ? Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: AppColors.accent,
                        )
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(size),
                ),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    _settings.setFontSize(picked);
    setState(() {});
  }

  Future<void> _pickHomeView() async {
    final picked = await _pickOption<AppHomeView>(
      title: '默认视图',
      values: AppHomeView.values,
      current: _settings.homeView,
      labelOf: (value) => value.label,
    );
    if (picked == null || !mounted) return;
    _settings.setHomeView(picked);
    setState(() {});
  }

  /// Shared single-choice sheet for the three preference rows.
  Future<T?> _pickOption<T>({
    required String title,
    required List<T> values,
    required T current,
    required String Function(T value) labelOf,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ),
              for (final value in values)
                ListTile(
                  title: Text(
                    labelOf(value),
                    style: TextStyle(fontSize: 14, color: AppColors.ink2),
                  ),
                  trailing: value == current
                      ? Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: AppColors.accent,
                        )
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(value),
                ),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
  }

  Future<void> _toggleAppLock(bool value) async {
    if (value) {
      final pin = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _PinSetupDialog(title: '设置应用锁 PIN'),
      );
      if (pin == null) return;
      AppLock.instance.enableWithPin(pin);
      await SecureScreen.apply();
      if (!mounted) return;
      setState(() {});
      showActionToast(context, '应用锁已开启');
    } else {
      if (!await _verifyPinPrompt(title: '关闭应用锁')) return;
      AppLock.instance.disable();
      await SecureScreen.apply();
      if (!mounted) return;
      setState(() {});
      showActionToast(context, '应用锁已关闭');
    }
  }

  Future<void> _changePin() async {
    final pin = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _PinSetupDialog(title: '修改 PIN'),
    );
    if (pin == null || !mounted) return;
    AppLock.instance.setPin(pin);
    setState(() {});
    showActionToast(context, 'PIN 已更新');
  }

  Future<void> _pickLockTimeout() async {
    final picked = await _pickOption<LockTimeout>(
      title: '自动锁定',
      values: LockTimeout.values,
      current: AppLock.instance.timeout,
      labelOf: (value) => value.label,
    );
    if (picked == null || !mounted) return;
    AppLock.instance.setTimeout(picked);
    setState(() {});
  }

  void _toggleBiometric(bool value) {
    AppLock.instance.setBiometric(value);
    setState(() {});
  }

  Future<void> _toggleSecure(bool value) async {
    AppLock.instance.setBlockScreenshot(value);
    await SecureScreen.apply();
    if (mounted) setState(() {});
  }

  /// Asks for the current PIN before a destructive security change (F-56).
  Future<bool> _verifyPinPrompt({required String title}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _VerifyPinDialog(title: title),
    );
    return result ?? false;
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 2, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: AppColors.ink2,
        ),
      ),
    );
  }

  Widget _choiceTile({
    required String title,
    required String value,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return _actionTile(
      icon: null,
      title: title,
      subtitle: subtitle,
      value: value,
      onTap: onTap,
    );
  }

  Widget _switchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 14, color: AppColors.ink),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.5,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeTrackColor: AppColors.accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _actionTile({
    IconData? icon,
    required String title,
    String? subtitle,
    String? value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: AppColors.muted),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 14, color: AppColors.ink),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (value != null) ...[
              Text(
                value,
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(width: 4),
            ],
            Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

/// Two-step PIN entry with digits-only inputs (F-54).
class _PinSetupDialog extends StatefulWidget {
  const _PinSetupDialog({required this.title});

  final String title;

  @override
  State<_PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends State<_PinSetupDialog> {
  final TextEditingController _pinCtrl = TextEditingController();
  final TextEditingController _confirmCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pinCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final pin = _pinCtrl.text;
    if (!AppLock.isValidPin(pin)) {
      setState(() => _error = 'PIN 需为 4~6 位数字');
      return;
    }
    if (pin != _confirmCtrl.text) {
      setState(() => _error = '两次输入的 PIN 不一致');
      return;
    }
    Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'PIN 只以加盐哈希保存在本机，忘记后无法找回。',
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pinCtrl,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'PIN（4~6 位）',
                counterText: '',
              ),
            ),
            TextField(
              controller: _confirmCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '再次输入 PIN',
                counterText: '',
              ),
              onSubmitted: (_) => _save(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(fontSize: 12, color: AppColors.danger),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('取消', style: TextStyle(color: AppColors.muted)),
        ),
        TextButton(
          onPressed: _save,
          child: Text('保存', style: TextStyle(color: AppColors.accentInk)),
        ),
      ],
    );
  }
}

/// PIN check dialog that owns its controller, so cancellation cannot leave
/// a disposed controller attached to a still-animating text field.
class _VerifyPinDialog extends StatefulWidget {
  const _VerifyPinDialog({required this.title});

  final String title;

  @override
  State<_VerifyPinDialog> createState() => _VerifyPinDialogState();
}

class _VerifyPinDialogState extends State<_VerifyPinDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (AppLock.instance.verifyPin(_controller.text)) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _error = AppLock.instance.isLockedOut ? '错误次数过多，请稍后再试' : 'PIN 不正确';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'PIN',
              counterText: '',
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(fontSize: 12, color: AppColors.danger),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('取消', style: TextStyle(color: AppColors.muted)),
        ),
        TextButton(
          onPressed: _submit,
          child: Text('确认', style: TextStyle(color: AppColors.accentInk)),
        ),
      ],
    );
  }
}
