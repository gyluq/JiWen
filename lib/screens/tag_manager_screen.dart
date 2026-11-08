import 'package:flutter/material.dart';

import '../data/notes_db.dart';
import '../models/tag.dart';
import '../theme.dart';
import '../util/tag_colors.dart';
import '../widgets/note_action_sheet.dart';
import '../widgets/tag_chip.dart';

/// Tag CRUD screen (requirement F-20/F-22).
class TagManagerScreen extends StatefulWidget {
  const TagManagerScreen({super.key});

  @override
  State<TagManagerScreen> createState() => _TagManagerScreenState();
}

class _TagManagerScreenState extends State<TagManagerScreen> {
  List<Tag> _tags = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() => _tags = NotesDb.instance.listTags());
  }

  Future<void> _createTag() async {
    final name = await _promptTagName(title: '新建标签');
    if (name == null || !mounted) return;
    NotesDb.instance.createTag(name);
    _reload();
  }

  Future<void> _renameTag(Tag tag) async {
    final name = await _promptTagName(title: '重命名标签', initial: tag.name);
    if (name == null || !mounted) return;
    if (!NotesDb.instance.renameTag(tag.id, name)) {
      showActionToast(context, '已有同名标签');
      return;
    }
    _reload();
  }

  Future<void> _deleteTag(Tag tag) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          '删除标签',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        content: Text(
          '「${tag.name}」将从所有笔记中移除，笔记本身不会被删除。',
          style: TextStyle(
            fontSize: 13,
            height: 1.7,
            color: AppColors.ink2,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('取消', style: TextStyle(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('删除', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    NotesDb.instance.deleteTag(tag.id);
    _reload();
  }

  Future<void> _pickTagColor(Tag tag) async {
    final picked = await showModalBottomSheet<int>(
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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '标签颜色',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    for (final value in kTagColorValues)
                      InkWell(
                        onTap: () => Navigator.of(sheetContext).pop(value),
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Color(value),
                            shape: BoxShape.circle,
                          ),
                          child: tag.color == value
                              ? const Icon(
                                  Icons.check_rounded,
                                  size: 18,
                                  color: Color(0xFFFFF8F1),
                                )
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    NotesDb.instance.updateTagColor(tag.id, picked);
    _reload();
  }

  Future<String?> _promptTagName({
    required String title,
    String initial = '',
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => _TagNameDialog(title: title, initial: initial),
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
          '标签管理',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _createTag,
            tooltip: '新建标签',
            icon: Icon(
              Icons.add_rounded,
              size: 22,
              color: AppColors.ink2,
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              '点击标签可重命名；点颜色圆点可设置标签颜色。',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
          Expanded(
            child: _tags.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 12, 32),
                    itemCount: _tags.length,
                    separatorBuilder: (_, _) =>
                        Container(height: 1, color: AppColors.line),
                    itemBuilder: (context, index) {
                      final tag = _tags[index];
                      return InkWell(
                        onTap: () => _renameTag(tag),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              TagChip(
                                label: tag.name,
                                colorValue: tag.color,
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                onPressed: () => _pickTagColor(tag),
                                tooltip: '标签颜色',
                                visualDensity: VisualDensity.compact,
                                icon: Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    color: tag.color == 0
                                        ? AppColors.tagBg
                                        : Color(tag.color),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: AppColors.line),
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${tag.noteCount} 条',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.muted,
                                ),
                              ),
                              IconButton(
                                onPressed: () => _deleteTag(tag),
                                tooltip: '删除标签',
                                visualDensity: VisualDensity.compact,
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sell_outlined, size: 40, color: AppColors.muted),
          const SizedBox(height: 14),
          Text(
            '还没有标签',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.ink2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '在笔记里添加标签，或点右上角新建',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

/// The dialog owns the text controller so it survives until the route is
/// fully removed, instead of being disposed while the exit animation runs.
class _TagNameDialog extends StatefulWidget {
  const _TagNameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_TagNameDialog> createState() => _TagNameDialogState();
}

class _TagNameDialogState extends State<_TagNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        widget.title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 20,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        style: TextStyle(fontSize: 14, color: AppColors.ink),
        decoration: InputDecoration(
          hintText: '标签名称',
          hintStyle: TextStyle(fontSize: 13, color: AppColors.muted),
          counterText: '',
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: AppColors.accent),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('取消', style: TextStyle(color: AppColors.muted)),
        ),
        TextButton(
          onPressed: _submit,
          child: Text('确定', style: TextStyle(color: AppColors.accent)),
        ),
      ],
    );
  }
}
