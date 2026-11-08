import 'package:flutter/material.dart';

import '../data/notes_db.dart';
import '../models/note.dart';
import '../theme.dart';
import '../util/text_import.dart';

/// Batch import from pasted text or a picked .txt/.md file (F-40 / F-41).
///
/// Nothing is written until the user confirms the previewed split, so an
/// accidental separator can be corrected first.
class TextImportScreen extends StatefulWidget {
  const TextImportScreen({super.key, this.initialText = '', this.sourceName});

  final String initialText;

  /// File name shown when the text came from a picked file (F-41).
  final String? sourceName;

  @override
  State<TextImportScreen> createState() => _TextImportScreenState();
}

class _TextImportScreenState extends State<TextImportScreen> {
  late final TextEditingController _textCtrl = TextEditingController(
    text: widget.initialText,
  );
  final TextEditingController _customCtrl = TextEditingController();
  ImportSeparator _separator = ImportSeparator.blankLines;
  List<String> _chunks = const [];

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(_refresh);
    _customCtrl.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _customCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(
      () => _chunks = splitImportText(
        _textCtrl.text,
        _separator,
        customDelimiter: _customCtrl.text,
      ),
    );
  }

  Future<void> _import() async {
    if (_chunks.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('没有可导入的内容', style: TextStyle(fontSize: 13)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    final base = DateTime.now().millisecondsSinceEpoch;
    for (var index = 0; index < _chunks.length; index++) {
      final chunk = _chunks[index];
      final stamp = base + index;
      NotesDb.instance.upsert(
        Note(
          id: newNoteId(),
          title: importTitleOf(chunk),
          body: importBodyOf(chunk),
          createdAt: stamp,
          updatedAt: stamp,
        ),
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop(_chunks.length);
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
          '批量导入文本',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
              child: Text(
                widget.sourceName == null
                    ? '粘贴多段文本，按分隔符拆分后可预览再导入。'
                    : '来自文件「${widget.sourceName}」，确认拆分结果后导入。',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _textCtrl,
                minLines: 4,
                maxLines: 8,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: AppColors.ink,
                ),
                decoration: InputDecoration(
                  hintText: '在这里粘贴文本',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: AppColors.muted,
                  ),
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.all(14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.accent),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '分隔符',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  for (final separator in ImportSeparator.values)
                    _separatorChip(separator),
                ],
              ),
            ),
            if (_separator == ImportSeparator.custom)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: TextField(
                  controller: _customCtrl,
                  maxLength: 10,
                  style: TextStyle(fontSize: 13, color: AppColors.ink),
                  decoration: InputDecoration(
                    hintText: '输入分隔符，例如 ###',
                    hintStyle: TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                    counterText: '',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    filled: true,
                    fillColor: AppColors.surface,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.accent),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Row(
                children: [
                  Text(
                    '预览 · 共 ${_chunks.length} 条',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink2,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _chunks.isEmpty
                  ? Center(
                      child: Text(
                        '输入内容后在此查看拆分结果',
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
                      itemCount: _chunks.length,
                      separatorBuilder: (_, _) =>
                          Container(height: 1, color: AppColors.line),
                      itemBuilder: (context, index) =>
                          _previewItem(index, _chunks[index]),
                    ),
            ),
            Container(
              decoration: BoxDecoration(
                color: AppColors.bg,
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton(
                  onPressed: _chunks.isEmpty ? null : _import,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: const Color(0xFFFFF8F1),
                    disabledBackgroundColor: AppColors.line,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(
                    _chunks.isEmpty ? '导入' : '导入 ${_chunks.length} 条笔记',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _separatorChip(ImportSeparator separator) {
    final selected = separator == _separator;
    return InkWell(
      onTap: () => setState(() => _separator = separator),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.line,
          ),
        ),
        child: Text(
          separator.label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? AppColors.accentInk : AppColors.ink2,
          ),
        ),
      ),
    );
  }

  Widget _previewItem(int index, String chunk) {
    final body = importBodyOf(chunk);
    final lineCount = body.isEmpty ? 0 : body.split('\n').length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${index + 1}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  importTitleOf(chunk),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body.isEmpty ? '（仅标题）' : body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$lineCount 行',
            style: TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
