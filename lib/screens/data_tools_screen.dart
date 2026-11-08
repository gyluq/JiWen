import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/backup.dart';
import '../data/exporter.dart';
import '../data/notes_db.dart';
import '../theme.dart';
import '../util/share_file.dart';
import '../util/time_text.dart';
import '../widgets/note_action_sheet.dart';
import 'text_import_screen.dart';

/// Entry point for export, import and backup (F-36 ~ F-44).
class DataToolsScreen extends StatefulWidget {
  const DataToolsScreen({super.key});

  @override
  State<DataToolsScreen> createState() => _DataToolsScreenState();
}

class _DataToolsScreenState extends State<DataToolsScreen> {
  List<BackupEntry> _backups = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reloadBackups();
  }

  Future<void> _reloadBackups() async {
    final entries = await BackupService.instance.listBackups();
    if (!mounted) return;
    setState(() => _backups = entries);
  }

  /// Runs one operation with the progress bar and error handling shared.
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on FormatException catch (error) {
      if (mounted) showActionToast(context, error.message);
    } catch (_) {
      if (mounted) showActionToast(context, '操作失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportAllZip() async {
    await _run(() async {
      final file = await NoteExporter.instance.exportAllZip();
      await shareFile(file, subject: '记问全部笔记');
    });
  }

  Future<void> _exportJson() async {
    await _run(() async {
      final file = await BackupService.instance.exportJsonFile();
      await shareFile(file, subject: '记问备份');
    });
  }

  Future<void> _manualBackup() async {
    await _run(() async {
      await BackupService.instance.createBackup();
      await _reloadBackups();
      if (mounted) showActionToast(context, '备份已生成');
    });
  }

  Future<void> _pasteImport() async {
    final count = await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => const TextImportScreen()),
    );
    if (count == null || !mounted) return;
    showActionToast(context, '已导入 $count 条笔记');
  }

  Future<void> _fileImport() async {
    await _run(() async {
      final picked = await FilePicker.pickFile(dialogTitle: '选择文本文件');
      if (picked == null) return;
      final name = picked.name.toLowerCase();
      final supported =
          name.endsWith('.txt') ||
          name.endsWith('.md') ||
          name.endsWith('.markdown');
      if (!supported) {
        if (mounted) showActionToast(context, '仅支持 .txt / .md 文件');
        return;
      }
      final text = utf8.decode(await picked.readAsBytes(), allowMalformed: true);
      if (!mounted) return;
      final count = await Navigator.of(context).push<int>(
        MaterialPageRoute(
          builder: (_) =>
              TextImportScreen(initialText: text, sourceName: picked.name),
        ),
      );
      if (count != null && mounted) {
        showActionToast(context, '已导入 $count 条笔记');
      }
    });
  }

  Future<void> _importJson() async {
    await _run(() async {
      final picked = await FilePicker.pickFile(dialogTitle: '选择备份文件');
      if (picked == null) return;
      final name = picked.name.toLowerCase();
      if (!name.endsWith('.json') && !name.endsWith('.zip')) {
        if (mounted) showActionToast(context, '请选择 .json 或 .zip 备份文件');
        return;
      }
      final bundle = BackupService.instance.decodeBundle(
        picked.name,
        await picked.readAsBytes(),
      );
      final duplicates = NotesDb.instance.countDuplicateNotes(bundle.payload);

      bool? overwrite;
      if (duplicates > 0) {
        if (!mounted) return;
        overwrite = await _askDuplicatePolicy(duplicates);
        if (overwrite == null) return;
      }

      final result = await BackupService.instance.importBundle(
        bundle,
        overwriteDuplicates: overwrite ?? true,
      );
      if (mounted) {
        showActionToast(
          context,
          '导入完成：写入 ${result.imported} 条，跳过 ${result.skipped} 条',
        );
      }
    });
  }

  /// Returns true to overwrite existing notes, false to skip them, null to
  /// abort the import (F-39).
  Future<bool?> _askDuplicatePolicy(int duplicates) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          '发现重复笔记',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        content: Text(
          '有 $duplicates 条笔记与本地笔记 ID 相同。覆盖会用备份内容替换这些笔记，跳过则保留本地版本。',
          style: TextStyle(fontSize: 13, height: 1.7, color: AppColors.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('取消', style: TextStyle(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('跳过', style: TextStyle(color: AppColors.ink2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('覆盖', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  Future<void> _restore(BackupEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          '恢复备份',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        content: Text(
          '将用 ${formatFullTime(entry.modified.millisecondsSinceEpoch)} 的备份替换当前全部笔记、标签与附件记录，此操作无法撤销。',
          style: TextStyle(fontSize: 13, height: 1.7, color: AppColors.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('取消', style: TextStyle(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('恢复', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _run(() async {
      final bundle = await BackupService.instance.readBundle(entry.file);
      final result = await BackupService.instance.restoreBundle(bundle);
      if (mounted) {
        showActionToast(context, '已恢复 ${result.imported} 条笔记');
      }
    });
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
          '数据与备份',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        bottom: _busy
            ? PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: AppColors.accent,
                  backgroundColor: AppColors.line,
                ),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '数据只保存在本机应用私有目录，卸载应用会全部清除。建议定期导出 ZIP 或 JSON 备份。',
              style: TextStyle(
                fontSize: 12,
                height: 1.7,
                color: AppColors.accentInk,
              ),
            ),
          ),
          _section('导出'),
          _actionTile(
            Icons.archive_outlined,
            '导出全部为 ZIP',
            '每条笔记一个 .md，图片统一放入 assets/',
            _exportAllZip,
          ),
          _actionTile(
            Icons.data_object_rounded,
            '导出 JSON 备份',
            '含笔记、标签与附件路径；图片请用本机备份',
            _exportJson,
          ),
          _section('导入'),
          _actionTile(
            Icons.content_paste_rounded,
            '粘贴文本批量导入',
            '选择分隔符拆分，导入前可预览',
            _pasteImport,
          ),
          _actionTile(
            Icons.upload_file_rounded,
            '从文件导入',
            '支持 .txt 与 .md，同样先预览再导入',
            _fileImport,
          ),
          _actionTile(
            Icons.settings_backup_restore_rounded,
            '导入备份文件',
            '支持 .zip 与 .json，重复笔记可选择覆盖或跳过',
            _importJson,
          ),
          _section('本地备份'),
          Padding(
            padding: EdgeInsets.fromLTRB(2, 0, 2, 8),
            child: Text(
              '每天首次启动或累计修改 50 次后自动备份，保留最近 5 份。',
              style: TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ),
          _actionTile(
            Icons.save_rounded,
            '立即备份',
            '生成含图片的完整备份并保留在应用内',
            _manualBackup,
          ),
          if (_backups.isEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(2, 8, 2, 0),
              child: Text(
                '暂无本地备份',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            )
          else
            for (final entry in _backups) _backupTile(entry),
        ],
      ),
    );
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

  Widget _actionTile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: _busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.muted),
            const SizedBox(width: 14),
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
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppColors.muted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _backupTile(BackupEntry entry) {
    return InkWell(
      onTap: _busy ? null : () => _restore(entry),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 20,
              color: AppColors.muted,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatFullTime(entry.modified.millisecondsSinceEpoch),
                    style: TextStyle(fontSize: 13, color: AppColors.ink),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_formatSize(entry.size)} · '
                    '${entry.hasImages ? '含图片' : '无图片'} · 点击恢复',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.restore_rounded,
              size: 18,
              color: AppColors.accent,
            ),
          ],
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
