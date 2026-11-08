import 'dart:async';

import 'package:flutter/material.dart';

import '../data/notes_db.dart';
import '../models/note.dart';
import '../models/tag.dart';
import '../theme.dart';
import '../widgets/note_action_sheet.dart';
import '../widgets/note_list_tile.dart';
import '../widgets/tag_picker_sheet.dart';
import 'note_detail_screen.dart';

/// Full-text search over titles, bodies and tags (F-28 / F-29).
///
/// The list screen no longer owns a search field; this screen starts empty so
/// the result area only appears once a keyword is typed.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _ctrl = TextEditingController();
  List<Note> _notes = const [];
  Map<String, List<Tag>> _tagsByNote = const {};
  String _term = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final term = value.trim();
    _debounce?.cancel();
    if (term.isEmpty) {
      setState(() {
        _term = '';
        _notes = const [];
        _tagsByNote = const {};
      });
      return;
    }
    setState(() => _term = term);
    _debounce = Timer(const Duration(milliseconds: 200), () {
      _runSearch(term);
    });
  }

  void _submit(String value) {
    final term = value.trim();
    if (term.isEmpty) return;
    _debounce?.cancel();
    FocusScope.of(context).unfocus();
    _runSearch(term, record: true);
  }

  void _runSearch(String term, {bool record = false}) {
    final db = NotesDb.instance;
    if (record) db.addSearchHistory(term);
    final notes = db.listNotes(query: term, sort: db.loadSortOrder());
    final tagsByNote = db.tagsOfNotes(notes.map((note) => note.id));
    if (!mounted) return;
    setState(() {
      _term = term;
      _notes = notes;
      _tagsByNote = tagsByNote;
    });
  }

  void _applyHistory(String term) {
    _ctrl.value = TextEditingValue(
      text: term,
      selection: TextSelection.collapsed(offset: term.length),
    );
    _debounce?.cancel();
    _runSearch(term, record: true);
  }

  void _removeHistory(String term) {
    NotesDb.instance.removeSearchHistory(term);
    setState(() {});
  }

  void _clearHistory() {
    NotesDb.instance.clearSearchHistory();
    setState(() {});
  }

  void _clearQuery() {
    _debounce?.cancel();
    _ctrl.clear();
    setState(() {
      _term = '';
      _notes = const [];
      _tagsByNote = const {};
    });
  }

  void _refresh() {
    if (_term.isEmpty) {
      setState(() {
        _notes = const [];
        _tagsByNote = const {};
      });
      return;
    }
    _runSearch(_term);
  }

  Future<void> _openDetail(Note note) async {
    final term = _term.trim();
    if (term.isNotEmpty) NotesDb.instance.addSearchHistory(term);
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NoteDetailScreen(note: note, query: term),
      ),
    );
    if (!mounted) return;
    _refresh();
    if (deleted == true) {
      showUndoToast(context, '已移入回收站', () {
        NotesDb.instance.restore(note.id);
        _refresh();
      });
    }
  }

  Future<void> _editTags(Note note) async {
    final current = NotesDb.instance
        .tagsOfNote(note.id)
        .map((tag) => tag.id)
        .toSet();
    final selected = await showTagPicker(context, selected: current);
    if (selected == null || !mounted) return;
    NotesDb.instance.setNoteTags(note.id, selected);
    _refresh();
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
        _refresh();
      });
      _refresh();
      return;
    }
    if (message != null) showActionToast(context, message);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: '返回',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 34,
                      minHeight: 34,
                    ),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 19,
                    ),
                    color: AppColors.ink,
                  ),
                  const SizedBox(width: 4),
                  Expanded(child: _buildField()),
                ],
              ),
            ),
            if (_term.isEmpty) ...[
              _buildHistory(),
              Expanded(child: _buildInitialHint()),
            ] else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                child: Row(
                  children: [
                    Text(
                      '${_notes.length} 条结果 · 全文匹配',
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _notes.isEmpty
                    ? _buildNoResult()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                        itemCount: _notes.length,
                        separatorBuilder: (_, _) =>
                            Container(height: 1, color: AppColors.line),
                        itemBuilder: (context, index) {
                          final note = _notes[index];
                          return NoteListTile(
                            note: note,
                            tags: _tagsByNote[note.id] ?? const [],
                            query: _term,
                            onTap: () => _openDetail(note),
                            onLongPress: () => _showActions(note),
                          );
                        },
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildField() {
    return TextField(
      controller: _ctrl,
      autofocus: true,
      onChanged: _onChanged,
      onSubmitted: _submit,
      textInputAction: TextInputAction.search,
      style: TextStyle(fontSize: 13, color: AppColors.ink),
      decoration: InputDecoration(
        hintText: '搜索笔记或标签',
        hintStyle: TextStyle(fontSize: 13, color: AppColors.muted),
        prefixIcon: Icon(Icons.search, size: 17, color: AppColors.muted),
        suffixIcon: _ctrl.text.isEmpty
            ? null
            : IconButton(
                onPressed: _clearQuery,
                tooltip: '清空',
                icon: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: AppColors.muted,
                ),
              ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 11),
        filled: true,
        fillColor: AppColors.surface,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.accent),
        ),
      ),
    );
  }

  Widget _buildHistory() {
    final history = NotesDb.instance.searchHistory();
    if (history.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '最近搜索',
                style: TextStyle(fontSize: 11, color: AppColors.muted),
              ),
              const Spacer(),
              InkWell(
                onTap: _clearHistory,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    '清空',
                    style: TextStyle(fontSize: 11, color: AppColors.accentInk),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [for (final term in history) _historyChip(term)],
          ),
        ],
      ),
    );
  }

  Widget _historyChip(String term) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.tagBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _applyHistory(term),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 5, 3, 5),
              child: Text(
                term,
                style: TextStyle(fontSize: 12, color: AppColors.ink2),
              ),
            ),
          ),
          InkWell(
            onTap: () => _removeHistory(term),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(3, 5, 9, 5),
              child: Icon(
                Icons.close_rounded,
                size: 13,
                color: AppColors.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitialHint() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 96),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.manage_search_rounded, size: 34, color: AppColors.muted),
            const SizedBox(height: 10),
            Text(
              '输入关键词开始搜索',
              style: TextStyle(fontSize: 13, color: AppColors.ink2),
            ),
            const SizedBox(height: 5),
            Text(
              '支持标题、正文与标签',
              style: TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResult() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 72),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 34, color: AppColors.muted),
            const SizedBox(height: 10),
            Text(
              '没有匹配的笔记',
              style: TextStyle(fontSize: 13, color: AppColors.ink2),
            ),
            const SizedBox(height: 5),
            Text(
              '换个关键词试试',
              style: TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
