import 'package:flutter/material.dart';

import '../data/attachments.dart';
import '../data/notes_db.dart';
import '../models/note.dart';
import '../theme.dart';
import '../widgets/note_action_sheet.dart';

/// Recycle bin: notes deleted within the last 30 days can be restored (F-04).
class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  List<Note> _notes = const [];

  @override
  void initState() {
    super.initState();
    _notes = NotesDb.instance.listTrashed();
  }

  void _reload() {
    setState(() => _notes = NotesDb.instance.listTrashed());
  }

  void _restore(Note note) {
    NotesDb.instance.restore(note.id);
    _reload();
    showActionToast(context, '已恢复');
  }

  Future<void> _purge(Note note) async {
    final confirmed = await _confirm(
      title: '彻底删除？',
      message: '「${note.title.isEmpty ? '无标题' : note.title}」删除后无法恢复。',
      confirmLabel: '删除',
    );
    if (confirmed != true || !mounted) return;
    final paths = NotesDb.instance.purge(note.id);
    AttachmentStore.instance.deleteReferences(paths);
    _reload();
    showActionToast(context, '已彻底删除');
  }

  Future<void> _empty() async {
    final count = _notes.length;
    if (count == 0) return;
    final confirmed = await _confirm(
      title: '清空回收站？',
      message: '将彻底删除 $count 条笔记，删除后无法恢复。',
      confirmLabel: '清空',
    );
    if (confirmed != true || !mounted) return;
    final paths = NotesDb.instance.purgeAll();
    AttachmentStore.instance.deleteReferences(paths);
    _reload();
    showActionToast(context, '回收站已清空');
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        content: Text(
          message,
          style: TextStyle(
            fontSize: 13,
            height: 1.6,
            color: AppColors.ink2,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            style: TextButton.styleFrom(foregroundColor: AppColors.muted),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
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
          '回收站',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _notes.isEmpty ? null : _empty,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.muted,
              disabledForegroundColor: AppColors.muted.withValues(alpha: 0.4),
            ),
            child: const Text('清空', style: TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _notes.isEmpty ? _buildEmptyState() : _buildList(),
      ),
    );
  }

  Widget _buildList() {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(20, 6, 20, 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.line),
          ),
          child: Text(
            '删除的笔记会保留 30 天，之后自动清理。清理后无法恢复。',
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: AppColors.muted,
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            itemCount: _notes.length,
            separatorBuilder: (_, _) => Container(height: 1, color: AppColors.line),
            itemBuilder: (context, index) => _buildItem(_notes[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildItem(Note note) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            note.title.isEmpty ? '无标题' : note.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.45,
              letterSpacing: -0.2,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _deletedLine(note),
            style: TextStyle(fontSize: 11.5, color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildAction('恢复', AppColors.accentInk, () => _restore(note)),
              const SizedBox(width: 10),
              _buildAction('彻底删除', AppColors.danger, () => _purge(note)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAction(String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.line),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 12.5, color: color),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.delete_outline_rounded,
            size: 40,
            color: AppColors.muted,
          ),
          const SizedBox(height: 14),
          Text(
            '回收站是空的',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.ink2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '删除的笔记会在这里保留 30 天',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  String _deletedLine(Note note) {
    final deletedAt = DateTime.fromMillisecondsSinceEpoch(note.deletedAt!);
    final elapsed = DateTime.now().difference(deletedAt).inDays;
    final remaining = (30 - elapsed).clamp(0, 30);
    final hour = deletedAt.hour.toString().padLeft(2, '0');
    final minute = deletedAt.minute.toString().padLeft(2, '0');
    return '删除于 ${deletedAt.month}月${deletedAt.day}日 $hour:$minute · 剩余 $remaining 天';
  }
}
