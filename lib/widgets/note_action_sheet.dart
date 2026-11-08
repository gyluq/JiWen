import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/exporter.dart';
import '../data/notes_db.dart';
import '../models/note.dart';
import '../theme.dart';
import '../util/share_file.dart';
import '../util/time_text.dart';

/// Actions offered by the note action sheet (requirement R-02 / R-04).
enum NoteMenuAction { pin, favorite, tags, status, copy, share, export, delete }

/// Shows the bottom action sheet for a note and returns the chosen action.
Future<NoteMenuAction?> showNoteActionSheet(BuildContext context, Note note) {
  return showModalBottomSheet<NoteMenuAction>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
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
                      height: 1.4,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '更新于 ${formatFullTime(note.updatedAt)}',
                    style: TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: AppColors.line),
            _sheetItem(
              sheetContext,
              note.pinned ? Icons.push_pin : Icons.push_pin_outlined,
              note.pinned ? '取消置顶' : '置顶',
              NoteMenuAction.pin,
            ),
            _sheetItem(
              sheetContext,
              note.favorite ? Icons.star_rounded : Icons.star_border_rounded,
              note.favorite ? '取消收藏' : '收藏',
              NoteMenuAction.favorite,
            ),
            _sheetItem(
              sheetContext,
              Icons.sell_outlined,
              '编辑标签',
              NoteMenuAction.tags,
            ),
            _sheetItem(
              sheetContext,
              Icons.check_circle_outline_rounded,
              note.status == NoteStatus.todo ? '切换为已解答' : '切换为待解答',
              NoteMenuAction.status,
            ),
            _sheetItem(
              sheetContext,
              Icons.copy_rounded,
              '复制正文',
              NoteMenuAction.copy,
            ),
            _sheetItem(
              sheetContext,
              Icons.share_outlined,
              '分享 Markdown 文本',
              NoteMenuAction.share,
            ),
            _sheetItem(
              sheetContext,
              Icons.ios_share_rounded,
              '导出 Markdown',
              NoteMenuAction.export,
            ),
            Container(height: 1, color: AppColors.line),
            _sheetItem(
              sheetContext,
              Icons.delete_outline_rounded,
              '删除',
              NoteMenuAction.delete,
              color: AppColors.danger,
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _sheetItem(
  BuildContext sheetContext,
  IconData icon,
  String label,
  NoteMenuAction action, {
  Color? color,
}) {
  final ink = color ?? AppColors.ink;
  return InkWell(
    onTap: () => Navigator.of(sheetContext).pop(action),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color ?? AppColors.muted),
          const SizedBox(width: 14),
          Text(label, style: TextStyle(fontSize: 15, color: ink)),
        ],
      ),
    ),
  );
}

/// Applies a sheet action to [note] and persists it.
///
/// Toggles never touch `updated_at`, so pinning or flagging a note does not
/// reorder it against real edits. Returns a toast message when there is one.
String? applyNoteMenuAction(Note note, NoteMenuAction action) {
  switch (action) {
    case NoteMenuAction.pin:
      note.pinned = !note.pinned;
      NotesDb.instance.upsert(note);
    case NoteMenuAction.favorite:
      note.favorite = !note.favorite;
      NotesDb.instance.upsert(note);
    case NoteMenuAction.tags:
      // Handled by the caller, which opens the tag picker.
      break;
    case NoteMenuAction.status:
      note.status = note.status == NoteStatus.todo
          ? NoteStatus.done
          : NoteStatus.todo;
      NotesDb.instance.upsert(note);
    case NoteMenuAction.copy:
      Clipboard.setData(ClipboardData(text: note.body));
      return '已复制正文';
    case NoteMenuAction.share:
      // The caller opens the share sheet because it is asynchronous.
      break;
    case NoteMenuAction.export:
      // The caller runs the export because it is asynchronous.
      break;
    case NoteMenuAction.delete:
      NotesDb.instance.softDelete(note.id);
      return '已移入回收站';
  }
  return null;
}

/// Exports one note as a `.md` file and opens the share sheet (F-36).
Future<void> exportNoteMarkdown(BuildContext context, Note note) async {
  try {
    final file = await NoteExporter.instance.exportSingle(note);
    await shareFile(file, subject: note.title.isEmpty ? '记问导出' : note.title);
  } catch (_) {
    if (context.mounted) showActionToast(context, '导出失败，请重试');
  }
}

/// Shares a note as Markdown text (F-35).
Future<void> shareNoteText(BuildContext context, Note note) async {
  try {
    final tags = NotesDb.instance.tagsOfNote(note.id);
    final text = NoteExporter.instance.markdownFor(note, tags: tags);
    await shareText(
      text,
      subject: note.title.trim().isEmpty ? '记问笔记' : note.title.trim(),
    );
  } catch (_) {
    if (context.mounted) showActionToast(context, '分享失败，请重试');
  }
}

void showActionToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 13)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1400),
      ),
    );
}

/// Toast with a one-tap undo, used after a note is moved to the trash (R-02).
///
/// R-03 requires a five-second window for the swipe gesture; long-press
/// deletions keep the shorter default.
void showUndoToast(
  BuildContext context,
  String message,
  VoidCallback onUndo, {
  Duration duration = const Duration(seconds: 4),
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 13)),
        behavior: SnackBarBehavior.floating,
        duration: duration,
        action: SnackBarAction(
          label: '撤销',
          textColor: const Color(0xFFF6E4DB),
          onPressed: onUndo,
        ),
      ),
    );
}
