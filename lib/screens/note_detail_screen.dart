import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../data/notes_db.dart';
import '../models/note.dart';
import '../models/tag.dart';
import '../theme.dart';
import '../util/markdown_parser.dart';
import '../util/search_highlight.dart';
import '../util/time_text.dart';
import '../widgets/markdown_view.dart';
import '../widgets/note_action_sheet.dart';
import '../widgets/tag_chip.dart';
import '../widgets/tag_picker_sheet.dart';
import 'note_editor_screen.dart';

/// Read-only view of a note with the rendered Markdown body.
class NoteDetailScreen extends StatefulWidget {
  const NoteDetailScreen({super.key, required this.note, this.query = ''});

  final Note note;

  /// Active search keyword; hits are highlighted and the first one is
  /// scrolled into view (F-28).
  final String query;

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  late Note _note;
  List<Tag> _tags = const [];

  /// Reading list controller: item 0 is the header, items 1..N are the
  /// Markdown blocks and the last item is the bottom spacer. Addressing
  /// blocks by index is what makes outline jumps possible (F-57).
  final ItemScrollController _scrollController = ItemScrollController();
  final ItemPositionsListener _positionsListener =
      ItemPositionsListener.create();

  late MdDocument _document;
  List<MdOutlineEntry> _outline = const [];

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _reloadRelated();
    _reloadDocument();
    _scrollToSearchHit();
  }

  void _reloadRelated() {
    _tags = NotesDb.instance.tagsOfNote(_note.id);
  }

  void _reloadDocument() {
    _document = parseMarkdown(_note.body);
    _outline = extractOutline(_document);
  }

  /// Scrolls the first search hit into view (F-28); the title stays at the
  /// top when the hit is only there.
  void _scrollToSearchHit() {
    final hit = firstMatchBlock(_document, widget.query);
    if (hit == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.isAttached) return;
      _scrollController.jumpTo(index: hit + 1, alignment: 0.12);
    });
  }

  void _scrollToBlock(int blockIndex) {
    if (!_scrollController.isAttached) return;
    _scrollController.jumpTo(index: blockIndex + 1, alignment: 0);
  }

  /// Outline entry of the heading that owns the current viewport top.
  int _currentOutlineIndex() {
    if (_outline.isEmpty) return 0;
    final positions = _positionsListener.itemPositions.value;
    final blocksAtTop = <int>[];
    for (final position in positions) {
      if (position.itemLeadingEdge > 0.02) continue;
      final blockIndex = position.index - 1;
      if (blockIndex >= 0) blocksAtTop.add(blockIndex);
    }
    int topBlock;
    if (blocksAtTop.isNotEmpty) {
      topBlock = blocksAtTop.reduce((a, b) => a > b ? a : b);
    } else {
      final visible = positions
          .map((position) => position.index - 1)
          .where((index) => index >= 0)
          .toList();
      if (visible.isEmpty) return 0;
      topBlock = visible.reduce((a, b) => a < b ? a : b);
    }
    var current = 0;
    for (var index = 0; index < _outline.length; index++) {
      if (_outline[index].blockIndex <= topBlock) current = index;
    }
    return current;
  }

  Future<void> _showOutline() async {
    final current = _currentOutlineIndex();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return _OutlineSheet(
          entries: _outline,
          currentIndex: current,
          onSelected: (entry) {
            Navigator.of(sheetContext).pop();
            _scrollToBlock(entry.blockIndex);
          },
        );
      },
    );
  }

  void _persist() {
    NotesDb.instance.upsert(_note);
  }

  void _togglePin() {
    setState(() => _note.pinned = !_note.pinned);
    _persist();
  }

  void _toggleFavorite() {
    setState(() => _note.favorite = !_note.favorite);
    _persist();
  }

  void _toggleStatus() {
    setState(() {
      _note.status = _note.status == NoteStatus.todo
          ? NoteStatus.done
          : NoteStatus.todo;
    });
    _persist();
  }

  Future<void> _editTags() async {
    final current = _tags.map((tag) => tag.id).toSet();
    final selected = await showTagPicker(context, selected: current);
    if (selected == null || !mounted) return;
    NotesDb.instance.setNoteTags(_note.id, selected);
    setState(() => _tags = NotesDb.instance.tagsOfNote(_note.id));
  }

  Future<void> _showMoreActions() async {
    final action = await showNoteActionSheet(context, _note);
    if (action == null || !mounted) return;
    if (action == NoteMenuAction.tags) {
      await _editTags();
      return;
    }
    if (action == NoteMenuAction.share) {
      await shareNoteText(context, _note);
      return;
    }
    if (action == NoteMenuAction.export) {
      await exportNoteMarkdown(context, _note);
      return;
    }
    final message = applyNoteMenuAction(_note, action);
    if (action == NoteMenuAction.delete) {
      if (mounted) Navigator.of(context).pop(true);
      return;
    }
    setState(() {});
    if (message != null) showActionToast(context, message);
  }

  Future<void> _openEditor() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => NoteEditorScreen(note: _note)));
    if (!mounted) return;
    final latest = NotesDb.instance.findById(_note.id);
    if (latest == null) {
      // The editor drops a note that was emptied out.
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _note = latest;
      _reloadRelated();
      _reloadDocument();
    });
  }

  Widget _buildTags() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final tag in _tags)
          TagChip(label: tag.name, colorValue: tag.color, onTap: _editTags),
        TagChip(label: '＋ 添加标签', onTap: _editTags),
      ],
    );
  }

  /// Tags stay left, the answer status sits on the same row but is pushed to
  /// the right and drawn as an outlined capsule so it never reads as a tag.
  Widget _buildTagRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildTags()),
        const SizedBox(width: 8),
        _buildStatusChip(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _note.title.isEmpty ? '无标题' : _note.title;
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
        actions: [
          IconButton(
            onPressed: _togglePin,
            tooltip: _note.pinned ? '取消置顶' : '置顶',
            icon: Icon(
              _note.pinned ? Icons.push_pin : Icons.push_pin_outlined,
              size: 20,
              color: _note.pinned ? AppColors.accent : AppColors.ink2,
            ),
          ),
          IconButton(
            onPressed: _toggleFavorite,
            tooltip: _note.favorite ? '取消收藏' : '收藏',
            icon: Icon(
              _note.favorite ? Icons.star_rounded : Icons.star_border_rounded,
              size: 22,
              color: _note.favorite ? AppColors.accent : AppColors.ink2,
            ),
          ),
          if (_outline.length >= 2)
            IconButton(
              onPressed: _showOutline,
              tooltip: '大纲',
              icon: Icon(
                Icons.format_list_bulleted_rounded,
                size: 21,
                color: AppColors.ink2,
              ),
            ),
          IconButton(
            onPressed: _showMoreActions,
            tooltip: '更多',
            icon: Icon(
              Icons.more_horiz_rounded,
              size: 22,
              color: AppColors.ink2,
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ScrollablePositionedList.builder(
        itemScrollController: _scrollController,
        itemPositionsListener: _positionsListener,
        itemCount: _document.blocks.isEmpty
            ? 3
            : _document.blocks.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) return _buildHeader(title);
          if (_document.blocks.isEmpty) {
            if (index == 1) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  '还没有正文内容',
                  style: TextStyle(fontSize: 13, color: AppColors.muted),
                ),
              );
            }
            return const SizedBox(height: 96);
          }
          final blockIndex = index - 1;
          if (blockIndex >= _document.blocks.length) {
            return const SizedBox(height: 96);
          }
          // Blocks are built lazily so very long notes scroll smoothly
          // (F-33); the list still knows every index, which is what the
          // outline and search jumps rely on (F-28 / F-57).
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: MarkdownBlockView(
              block: _document.blocks[blockIndex],
              highlight: widget.query,
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openEditor,
        tooltip: '编辑笔记',
        backgroundColor: AppColors.accent,
        foregroundColor: const Color(0xFFFFF8F1),
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: const Icon(Icons.edit_rounded, size: 24),
      ),
    );
  }

  Widget _buildHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(_titleSpan(title), style: _titleStyle),
          const SizedBox(height: 10),
          Text(
            '更新于 ${formatFullTime(_note.updatedAt)} · 创建于 ${formatFullTime(_note.createdAt)}',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.muted,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 14),
          _buildTagRow(),
        ],
      ),
    );
  }

  TextStyle get _titleStyle => TextStyle(
    fontSize: 25,
    fontWeight: FontWeight.w700,
    height: 1.34,
    letterSpacing: -0.5,
    color: AppColors.ink,
  );

  TextSpan _titleSpan(String title) {
    final query = widget.query.trim();
    if (query.isEmpty) return TextSpan(text: title, style: _titleStyle);
    return TextSpan(
      children: [
        for (final run in highlightRuns(title, query))
          TextSpan(
            text: run.text,
            style: run.isHit
                ? _titleStyle.copyWith(
                    color: AppColors.accentInk,
                    backgroundColor: AppColors.accentSoft,
                  )
                : _titleStyle,
          ),
      ],
    );
  }

  Widget _buildStatusChip() {
    final todo = _note.status == NoteStatus.todo;
    final color = todo ? AppColors.accentInk : AppColors.muted;
    return InkWell(
      onTap: _toggleStatus,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 26,
        padding: const EdgeInsets.only(left: 9, right: 6),
        decoration: BoxDecoration(
          color: todo ? AppColors.accentSoft : AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: todo ? AppColors.accent : AppColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: todo ? AppColors.accent : AppColors.muted,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              todo ? '待解答' : '已解答',
              style: TextStyle(fontSize: 11.5, color: color),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, size: 15, color: color),
          ],
        ),
      ),
    );
  }
}

/// Half-screen outline sheet listing the H1-H3 headings of the note (F-57).
class _OutlineSheet extends StatelessWidget {
  const _OutlineSheet({
    required this.entries,
    required this.currentIndex,
    required this.onSelected,
  });

  final List<MdOutlineEntry> entries;

  /// Entry matching the heading at the top of the reading viewport.
  final int currentIndex;

  final ValueChanged<MdOutlineEntry> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.58,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.line),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '大纲',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${entries.length} 个标题 · 点击跳转',
                    style: TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: entries.length,
                itemBuilder: (context, index) =>
                    _buildEntry(entries[index], index == currentIndex),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Text(
                '仅列出正文中的 H1–H3 标题，不足两个标题时不显示入口',
                style: TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntry(MdOutlineEntry entry, bool active) {
    final level3 = entry.level >= 3;
    final indent = level3 ? 36.0 : 20.0;
    final color = active
        ? AppColors.accentInk
        : (level3 ? AppColors.muted : AppColors.ink2);
    return InkWell(
      onTap: () => onSelected(entry),
      child: Container(
        width: double.infinity,
        // The active entry carries a 3px rule on the left, so its text moves
        // in by the same amount to stay aligned with the other entries.
        padding: EdgeInsets.only(
          left: active ? indent - 3 : indent,
          right: 20,
          top: 9,
          bottom: 9,
        ),
        decoration: BoxDecoration(
          color: active ? AppColors.accentSoft : null,
          border: active
              ? Border(left: BorderSide(color: AppColors.accent, width: 3))
              : null,
        ),
        child: Text(
          entry.text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: level3 ? 13 : 14,
            height: 1.5,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: color,
          ),
        ),
      ),
    );
  }
}
