import 'package:flutter/material.dart';

import '../data/notes_db.dart';
import '../models/tag.dart';
import '../theme.dart';
import 'tag_chip.dart';

/// Opens a tag picker and returns the selected tag ids, or null on cancel.
Future<Set<String>?> showTagPicker(
  BuildContext context, {
  required Set<String> selected,
}) {
  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _TagPickerSheet(initial: selected),
  );
}

class _TagPickerSheet extends StatefulWidget {
  const _TagPickerSheet({required this.initial});

  final Set<String> initial;

  @override
  State<_TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends State<_TagPickerSheet> {
  final TextEditingController _queryCtrl = TextEditingController();
  late final Set<String> _selected = {...widget.initial};
  List<Tag> _tags = const [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tags = NotesDb.instance.listTags();
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  List<Tag> get _visible {
    final keyword = _query.trim().toLowerCase();
    if (keyword.isEmpty) return _tags;
    return _tags
        .where((tag) => tag.name.toLowerCase().contains(keyword))
        .toList();
  }

  bool get _hasExactTag {
    final keyword = _query.trim().toLowerCase();
    if (keyword.isEmpty) return true;
    return _tags.any((tag) => tag.name.toLowerCase() == keyword);
  }

  void _toggle(String tagId) {
    setState(() {
      if (!_selected.remove(tagId)) _selected.add(tagId);
    });
  }

  void _createTag() {
    final name = _queryCtrl.text.trim();
    if (name.isEmpty) return;
    final tag = NotesDb.instance.createTag(name);
    setState(() {
      _selected.add(tag.id);
      _queryCtrl.clear();
      _query = '';
      _tags = NotesDb.instance.listTags();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: (MediaQuery.sizeOf(context).height - bottomInset) * 0.8,
          ),
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
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                      '选择标签',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(_selected),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.accent,
                      ),
                      child: const Text(
                        '完成',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: TextField(
                  controller: _queryCtrl,
                  onChanged: (value) => setState(() => _query = value),
                  style: TextStyle(fontSize: 13, color: AppColors.ink),
                  decoration: InputDecoration(
                    hintText: '搜索或新建标签',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: AppColors.muted,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      size: 18,
                      color: AppColors.muted,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    filled: true,
                    fillColor: AppColors.bg,
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
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!_hasExactTag)
                        InkWell(
                          onTap: _createTag,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.add_circle_outline_rounded,
                                  size: 18,
                                  color: AppColors.accent,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '新建标签「${_query.trim()}」',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.accentInk,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (_visible.isEmpty && _hasExactTag)
                        Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: Text(
                            '还没有标签，输入名称即可新建',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final tag in _visible)
                              TagChip(
                                label: tag.name,
                                selected: _selected.contains(tag.id),
                                onTap: () => _toggle(tag.id),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
