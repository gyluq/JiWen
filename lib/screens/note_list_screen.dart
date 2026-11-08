import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_lock.dart';
import '../data/app_settings.dart';
import '../data/notes_db.dart';
import '../models/note.dart';
import '../models/tag.dart';
import '../theme.dart';
import '../widgets/note_action_sheet.dart';
import '../widgets/note_list_tile.dart';
import '../widgets/tag_chip.dart';
import '../widgets/tag_picker_sheet.dart';
import 'note_detail_screen.dart';
import 'note_editor_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'tag_manager_screen.dart';
import 'trash_screen.dart';

/// Updated-at windows offered by the time-range filter (F-23).
enum _TimeRange {
  any('时间范围', null),
  week('近 7 天', 7),
  month('近 30 天', 30),
  quarter('近 90 天', 90);

  const _TimeRange(this.label, this.days);

  final String label;
  final int? days;

  /// Epoch milliseconds lower bound, null for "any".
  int? get updatedSince {
    final value = days;
    if (value == null) return null;
    return DateTime.now()
        .subtract(Duration(days: value))
        .millisecondsSinceEpoch;
  }
}

class NoteListScreen extends StatefulWidget {
  const NoteListScreen({super.key});

  @override
  State<NoteListScreen> createState() => _NoteListScreenState();
}

class _NoteListScreenState extends State<NoteListScreen> {
  List<Note> _notes = const [];
  List<Tag> _tags = const [];
  Map<String, List<Tag>> _tagsByNote = const {};
  String? _tagId;
  NoteFilter _filter = NoteFilter.all;
  NoteSort _sort = NoteSort.updated;
  _TimeRange _timeRange = _TimeRange.any;
  bool _favoriteOnly = false;

  @override
  void initState() {
    super.initState();
    final settings = AppSettings.instance;
    _sort = NotesDb.instance.loadSortOrder();
    // F-48: the list opens on the preferred view.
    switch (settings.homeView) {
      case AppHomeView.all:
        break;
      case AppHomeView.todo:
        _filter = NoteFilter.todo;
      case AppHomeView.favorites:
        _favoriteOnly = true;
    }
    _reload();
    // F-49: opening the app goes straight into a new note. The lock screen
    // must stay on top, so it waits until the lock is disabled or next launch.
    if (settings.openToNewNote && !AppLock.instance.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openEditor();
      });
    }
  }

  void _reload() {
    final tags = NotesDb.instance.listTags();
    if (_tagId != null && !tags.any((tag) => tag.id == _tagId)) {
      _tagId = null;
    }
    final notes = NotesDb.instance.listNotes(
      filter: _filter,
      tagId: _tagId,
      favoriteOnly: _favoriteOnly,
      updatedSince: _timeRange.updatedSince,
      sort: _sort,
    );
    final tagsByNote = NotesDb.instance.tagsOfNotes(
      notes.map((note) => note.id),
    );
    setState(() {
      _tags = tags;
      _notes = notes;
      _tagsByNote = tagsByNote;
    });
  }

  void _onFilterChanged(NoteFilter filter) {
    if (_filter == filter) return;
    setState(() => _filter = filter);
    _reload();
  }

  void _onTagSelected(String tagId) {
    setState(() => _tagId = _tagId == tagId ? null : tagId);
    _reload();
  }

  void _toggleFavorites() {
    setState(() => _favoriteOnly = !_favoriteOnly);
    _reload();
  }

  Future<void> _pickTimeRange() async {
    final picked = await showModalBottomSheet<_TimeRange>(
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
                padding: EdgeInsets.fromLTRB(20, 16, 20, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '按更新时间筛选',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ),
              for (final range in _TimeRange.values)
                ListTile(
                  title: Text(
                    range.label,
                    style: TextStyle(fontSize: 14, color: AppColors.ink2),
                  ),
                  trailing: range == _timeRange
                      ? Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: AppColors.accent,
                        )
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(range),
                ),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() => _timeRange = picked);
    _reload();
  }

  /// Sort menu reuses the bottom sheet pattern of the time-range filter (F-25).
  Future<void> _pickSort() async {
    final picked = await showModalBottomSheet<NoteSort>(
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
                padding: EdgeInsets.fromLTRB(20, 16, 20, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '排序方式',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ),
              for (final sort in NoteSort.values)
                ListTile(
                  title: Text(
                    _sortLabel(sort),
                    style: TextStyle(fontSize: 14, color: AppColors.ink2),
                  ),
                  trailing: sort == _sort
                      ? Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: AppColors.accent,
                        )
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(sort),
                ),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
    if (picked == null || picked == _sort || !mounted) return;
    NotesDb.instance.saveSortOrder(picked);
    setState(() => _sort = picked);
    _reload();
  }

  String _sortLabel(NoteSort sort) {
    return switch (sort) {
      NoteSort.updated => '最近修改',
      NoteSort.created => '创建时间',
      NoteSort.title => '标题',
    };
  }

  void _clearFilters() {
    setState(() {
      _filter = NoteFilter.all;
      _tagId = null;
      _timeRange = _TimeRange.any;
      _favoriteOnly = false;
    });
    _reload();
  }

  Future<void> _openEditor([Note? note]) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => NoteEditorScreen(note: note)));
    _reload();
  }

  Future<void> _openDetail(Note note) async {
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => NoteDetailScreen(note: note)),
    );
    _reload();
    if (deleted == true && mounted) {
      showUndoToast(context, '已移入回收站', () {
        NotesDb.instance.restore(note.id);
        _reload();
      });
    }
  }

  Future<void> _openTagManager() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const TagManagerScreen()));
    _reload();
  }

  Future<void> _openTrash() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const TrashScreen()));
    _reload();
  }

  Future<void> _openSearch() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SearchScreen()));
    _reload();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    if (!mounted) return;
    // Re-read the font size and palette once the settings route closes.
    setState(_reload);
  }

  Future<void> _editTags(Note note) async {
    final current = NotesDb.instance
        .tagsOfNote(note.id)
        .map((tag) => tag.id)
        .toSet();
    final selected = await showTagPicker(context, selected: current);
    if (selected == null || !mounted) return;
    NotesDb.instance.setNoteTags(note.id, selected);
    _reload();
  }

  Future<void> _showActions(Note note) async {
    final action = await showNoteActionSheet(context, note);
    if (action == null || !mounted) return;
    if (action == NoteMenuAction.tags) {
      await _editTags(note);
      return;
    }
    if (action == NoteMenuAction.share) {
      await shareNoteText(context, note);
      return;
    }
    if (action == NoteMenuAction.export) {
      await exportNoteMarkdown(context, note);
      return;
    }
    final message = applyNoteMenuAction(note, action);
    if (action == NoteMenuAction.delete) {
      showUndoToast(context, message!, () {
        NotesDb.instance.restore(note.id);
        _reload();
      });
      _reload();
      return;
    }
    if (message != null) showActionToast(context, message);
    _reload();
  }

  /// Moves a note to the trash after a swipe and offers a five-second undo
  /// (R-03). The same soft-delete path backs the long-press menu.
  void _deleteWithUndo(Note note) {
    NotesDb.instance.softDelete(note.id);
    showUndoToast(
      context,
      '已移入回收站',
      () {
        NotesDb.instance.restore(note.id);
        _reload();
      },
      duration: const Duration(seconds: 5),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final notes = _notes;
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _openEditor,
        backgroundColor: AppColors.accent,
        foregroundColor: const Color(0xFFFFF8F1),
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: const Icon(Icons.add, size: 26),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  Text(
                    '记问',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                      color: AppColors.ink,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _toggleFavorites,
                    tooltip: '收藏',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                    icon: Icon(
                      _favoriteOnly
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      size: 18,
                      color: _favoriteOnly ? AppColors.accent : AppColors.ink2,
                    ),
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    onPressed: _openTrash,
                    tooltip: '回收站',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: AppColors.ink2,
                    ),
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    onPressed: _openTagManager,
                    tooltip: '标签管理',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                    icon: Icon(
                      Icons.sell_outlined,
                      size: 18,
                      color: AppColors.ink2,
                    ),
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    onPressed: _openSearch,
                    tooltip: '搜索',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                    icon: Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: AppColors.ink2,
                    ),
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    onPressed: _openSettings,
                    tooltip: '设置',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                    icon: Icon(
                      Icons.settings_outlined,
                      size: 18,
                      color: AppColors.ink2,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '共 ${notes.length} 条',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            _buildSegments(),
            _buildFilterRow(),
            Expanded(
              child: notes.isEmpty
                  ? _buildEmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
                      itemCount: notes.length,
                      separatorBuilder: (_, _) =>
                          Container(height: 1, color: AppColors.line),
                      itemBuilder: (context, index) {
                        final note = notes[index];
                        return _SwipeToDelete(
                          key: ValueKey<String>(note.id),
                          onDelete: () => _deleteWithUndo(note),
                          child: NoteListTile(
                            note: note,
                            tags: _tagsByNote[note.id] ?? const [],
                            onTap: () => _openDetail(note),
                            onLongPress: () => _showActions(note),
                            onTagTap: (tag) => _onTagSelected(tag.id),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Active conditions stay visible and can be removed one by one (F-23).
  Widget _buildFilterRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SizedBox(
        height: 28,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            if (_favoriteOnly) ...[
              TagChip(
                label: '收藏',
                selected: true,
                onTap: _toggleFavorites,
                onRemove: _toggleFavorites,
              ),
              const SizedBox(width: 8),
            ],
            if (_tags.isNotEmpty) ...[
              TagChip(
                label: '全部标签',
                selected: _tagId == null,
                onTap: _tagId == null
                    ? null
                    : () {
                        setState(() => _tagId = null);
                        _reload();
                      },
              ),
              const SizedBox(width: 8),
              for (final tag in _tags) ...[
                TagChip(
                  label: tag.name,
                  colorValue: tag.color,
                  selected: _tagId == tag.id,
                  onTap: () => _onTagSelected(tag.id),
                  onRemove: _tagId == tag.id
                      ? () {
                          setState(() => _tagId = null);
                          _reload();
                        }
                      : null,
                ),
                const SizedBox(width: 8),
              ],
            ],
            TagChip(
              label: _timeRange.label,
              selected: _timeRange != _TimeRange.any,
              onTap: _pickTimeRange,
              onRemove: _timeRange == _TimeRange.any
                  ? null
                  : () {
                      setState(() => _timeRange = _TimeRange.any);
                      _reload();
                    },
            ),
            const SizedBox(width: 8),
            TagChip(label: _sortLabel(_sort), onTap: _pickSort),
          ],
        ),
      ),
    );
  }

  Widget _buildSegments() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            _buildSegment(NoteFilter.all, '全部'),
            _buildSegment(NoteFilter.todo, '待解答'),
            _buildSegment(NoteFilter.done, '已解答'),
            _buildSegment(NoteFilter.pinned, '置顶'),
          ],
        ),
      ),
    );
  }

  Widget _buildSegment(NoteFilter filter, String label) {
    final selected = _filter == filter;
    return Expanded(
      child: InkWell(
        onTap: () => _onFilterChanged(filter),
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? const Color(0xFFFFF8F1) : AppColors.ink2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final filtered =
        _filter != NoteFilter.all ||
        _tagId != null ||
        _favoriteOnly ||
        _timeRange != _TimeRange.any;
    final String title;
    final String hint;
    if (_favoriteOnly) {
      title = _timeRange == _TimeRange.any ? '还没有收藏笔记' : '没有符合条件的收藏';
      hint = _timeRange == _TimeRange.any ? '在笔记详情页点右上角星标收藏' : '试试扩大时间范围';
    } else if (_timeRange != _TimeRange.any) {
      title = '该时间段暂无笔记';
      hint = '试试扩大时间范围';
    } else if (_tagId != null) {
      title = '该标签下暂无笔记';
      hint = '给笔记添加标签后，会出现在这里';
    } else if (_filter == NoteFilter.todo) {
      title = '暂无待解答笔记';
      hint = '记录问题后，答案可以慢慢补';
    } else if (_filter == NoteFilter.done) {
      title = '暂无已解答笔记';
      hint = '把已有答案的笔记标记为已解答';
    } else if (_filter == NoteFilter.pinned) {
      title = '还没有置顶笔记';
      hint = '长按笔记，选择「置顶」';
    } else {
      title = '还没有笔记';
      hint = '点右下角，记下第一个问题';
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _favoriteOnly ? Icons.star_border_rounded : Icons.notes_rounded,
            size: 40,
            color: AppColors.muted,
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.ink2,
            ),
          ),
          const SizedBox(height: 6),
          Text(hint, style: TextStyle(fontSize: 12, color: AppColors.muted)),
          if (filtered) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: _clearFilters,
              style: TextButton.styleFrom(foregroundColor: AppColors.accent),
              child: const Text('清空筛选', style: TextStyle(fontSize: 13)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Swipe-left delete affordance for the home list only (R-03).
///
/// Dragging left reveals a red action; the note is removed only after the
/// action is tapped. Rightward drags are ignored and the widget is not used by
/// the search results or recycle bin, so the system back gesture and those
/// lists stay untouched.
class _SwipeToDelete extends StatefulWidget {
  const _SwipeToDelete({super.key, required this.child, required this.onDelete});

  final Widget child;
  final VoidCallback onDelete;

  @override
  State<_SwipeToDelete> createState() => _SwipeToDeleteState();
}

class _SwipeToDeleteState extends State<_SwipeToDelete>
    with SingleTickerProviderStateMixin {
  static const double _actionWidth = 84;

  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  void _handleDelete() {
    // Reset before removing so a row that stays (e.g. undo path) is closed.
    _reveal.value = 0;
    widget.onDelete();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    // Positive delta is a rightward drag, which must not open the action.
    final next = (_reveal.value - delta / _actionWidth).clamp(0.0, 1.0);
    _reveal.value = next.toDouble();
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final bool open;
    if (velocity < -250) {
      open = true;
    } else if (velocity > 250) {
      open = false;
    } else {
      open = _reveal.value >= 0.5;
    }
    _reveal.animateTo(open ? 1 : 0, curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: _actionWidth,
                child: Material(
                  color: AppColors.danger,
                  child: InkWell(
                    onTap: _handleDelete,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: Color(0xFFFFF8F1),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '删除',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFFFF8F1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _reveal,
            builder: (context, child) => Transform.translate(
              offset: Offset(-_actionWidth * _reveal.value, 0),
              child: child,
            ),
            child: ColoredBox(color: AppColors.bg, child: widget.child),
          ),
        ],
      ),
    );
  }
}
