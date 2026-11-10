import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../data/app_settings.dart';
import '../data/attachments.dart';
import '../data/backup.dart';
import '../data/notes_db.dart';
import '../models/note.dart';
import '../models/tag.dart';
import '../theme.dart';
import '../util/markdown_edit.dart';
import '../widgets/markdown_view.dart';
import '../widgets/tag_chip.dart';
import '../widgets/tag_picker_sheet.dart';

class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({super.key, this.note});

  /// Null means a brand new note; the row is inserted on the first save.
  final Note? note;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  static const _autoSaveDelay = Duration(milliseconds: 1200);
  static const _historyDelay = Duration(milliseconds: 500);
  static const _historyLimit = 100;

  late final Note _note;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _bodyCtrl;
  final ValueNotifier<String> _status = ValueNotifier<String>('');
  final FocusNode _bodyFocus = FocusNode();
  final ValueNotifier<MarkdownFormatState> _format = ValueNotifier(
    const MarkdownFormatState(),
  );
  Timer? _timer;
  Timer? _historyTimer;
  final List<_EditorSnapshot> _history = [];
  int _historyIndex = 0;
  bool _restoring = false;
  bool _persisted = false;
  bool _dirty = false;
  bool _preview = false;
  List<Tag> _tags = const [];
  Set<String> _tagIds = {};
  bool _tagsDirty = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().millisecondsSinceEpoch;
    _note =
        widget.note ?? Note(id: newNoteId(), createdAt: now, updatedAt: now);
    _persisted = widget.note != null;
    if (_persisted) {
      _tags = NotesDb.instance.tagsOfNote(_note.id);
      _tagIds = _tags.map((tag) => tag.id).toSet();
    }
    _titleCtrl = TextEditingController(text: _note.title);
    _bodyCtrl = TextEditingController(text: _note.body);
    _titleCtrl.addListener(_onChanged);
    _bodyCtrl.addListener(_onBodyChanged);
    _format.value = inspectMarkdown(_bodyCtrl.value);
    _history.add(_snapshot());
    // F-01/F-49: a new note opens with the caret ready in the body.
    if (widget.note == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _bodyFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _titleCtrl.removeListener(_onChanged);
    _bodyCtrl.removeListener(_onBodyChanged);
    _timer?.cancel();
    _historyTimer?.cancel();
    _bodyFocus.dispose();
    _format.dispose();
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _status.dispose();
    super.dispose();
  }

  void _onBodyChanged() {
    _format.value = inspectMarkdown(_bodyCtrl.value);
    _onChanged();
  }

  /// Marks the editor dirty only when the text really differs, so caret moves
  /// alone do not trigger a save.
  void _onChanged() {
    _scheduleHistory();
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text;
    if (!_tagsDirty && title == _note.title && body == _note.body) return;
    _dirty = true;
    if (_timer == null) _status.value = '保存中…';
    _timer?.cancel();
    _timer = Timer(_autoSaveDelay, _saveNow);
  }

  _EditorSnapshot _snapshot() =>
      _EditorSnapshot(_titleCtrl.text, _bodyCtrl.text);

  bool get _canUndo => _historyIndex > 0;

  bool get _canRedo => _historyIndex < _history.length - 1;

  /// Coalesces a typing burst into one undo step (F-16).
  void _scheduleHistory() {
    if (_restoring) return;
    _historyTimer?.cancel();
    _historyTimer = Timer(_historyDelay, _commitHistory);
  }

  void _commitHistory() {
    _historyTimer?.cancel();
    final snapshot = _snapshot();
    if (_history[_historyIndex].sameAs(snapshot)) return;
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    _history.add(snapshot);
    if (_history.length > _historyLimit) _history.removeAt(0);
    _historyIndex = _history.length - 1;
    if (mounted) setState(() {});
  }

  void _undo() {
    _commitHistory();
    if (!_canUndo) return;
    _historyIndex--;
    _restore(_history[_historyIndex]);
  }

  void _redo() {
    if (!_canRedo) return;
    _historyIndex++;
    _restore(_history[_historyIndex]);
  }

  void _restore(_EditorSnapshot snapshot) {
    _restoring = true;
    _titleCtrl.value = TextEditingValue(
      text: snapshot.title,
      selection: TextSelection.collapsed(offset: snapshot.title.length),
    );
    _bodyCtrl.value = TextEditingValue(
      text: snapshot.body,
      selection: TextSelection.collapsed(offset: snapshot.body.length),
    );
    _format.value = inspectMarkdown(_bodyCtrl.value);
    _restoring = false;
    _onChanged();
    if (mounted) setState(() {});
  }

  void _saveNow() {
    _timer?.cancel();
    _timer = null;
    if (!_dirty) return;

    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text;
    final isEmpty = title.isEmpty && body.trim().isEmpty;

    if (isEmpty) {
      // Drop drafts that never received content.
      if (_persisted) {
        NotesDb.instance.delete(_note.id);
        _persisted = false;
      }
      _status.value = '';
      return;
    }

    _note
      ..title = title
      ..body = body
      ..updatedAt = DateTime.now().millisecondsSinceEpoch;
    NotesDb.instance.upsert(_note);
    if (_tagsDirty) {
      NotesDb.instance.setNoteTags(_note.id, _tagIds);
      _tagsDirty = false;
    }
    _persisted = true;
    _dirty = false;
    _status.value = '已保存';
    // F-43 also allows a backup after 50 accumulated note writes.
    unawaited(BackupService.instance.maybeAutoBackup());
  }

  Future<void> _editTags() async {
    final selected = await showTagPicker(context, selected: _tagIds);
    if (selected == null || !mounted) return;
    setState(() {
      _tagIds = selected;
      _tags = NotesDb.instance
          .listTags()
          .where((tag) => selected.contains(tag.id))
          .toList();
    });
    if (_persisted) {
      NotesDb.instance.setNoteTags(_note.id, _tagIds);
    } else {
      _tagsDirty = true;
      _saveNow();
    }
  }

  /// Persists before the route pops.
  ///
  /// Saving from dispose() is unsafe: the dispose callback can run only after
  /// the pop animation finishes, which is late enough for the next editor
  /// route to have loaded already. Such a stale instance would then overwrite
  /// newer content with its own older text.
  void _pop() {
    _saveNow();
    Navigator.of(context).pop();
  }

  void _applyToolbar(_ToolbarTool tool) {
    // Every toolbar tap answers back on the finger: without it a transform
    // that only nudges a marker reads as "the button did nothing".
    HapticFeedback.selectionClick();
    final value = _bodyCtrl.value;
    final edit = switch (tool) {
      _ToolbarTool.heading => cycleHeading(value),
      _ToolbarTool.list => toggleList(value),
      _ToolbarTool.task => toggleTaskList(value),
      _ToolbarTool.indent => indentLines(value),
      _ToolbarTool.outdent => outdentLines(value),
      _ToolbarTool.code => toggleCodeBlock(value),
      _ToolbarTool.codeSpan => toggleInlineCode(value),
      _ToolbarTool.bold => toggleBold(value),
      _ToolbarTool.italic => toggleItalic(value),
      _ToolbarTool.strike => toggleStrike(value),
      _ToolbarTool.table => insertTable(value),
      _ToolbarTool.divider => insertDivider(value),
      _ToolbarTool.link => insertLink(value),
      _ToolbarTool.image => null,
    };
    if (edit == null) {
      _pickImage();
      return;
    }
    _bodyCtrl.value = edit.value;
    // Re-read the format state from the text we just produced instead of
    // trusting the controller listener alone: on device the IME can re-attach
    // between the assignment and the listener, and a stale state leaves the
    // toolbar showing the previous line.
    _format.value = inspectMarkdown(_bodyCtrl.value);
    _bodyFocus.requestFocus();
  }

  /// Ticking a box in the preview is a real edit: it rewrites the source line
  /// and saves right away, because the preview is the only handle the user has
  /// on that row while reading.
  void _togglePreviewTask(int line) {
    final next = toggleTaskAtLine(_bodyCtrl.text, line);
    if (next == null) return;
    HapticFeedback.selectionClick();
    _bodyCtrl.value = TextEditingValue(
      text: next,
      selection: _bodyCtrl.selection,
    );
    _format.value = inspectMarkdown(_bodyCtrl.value);
    _saveNow();
    setState(() {});
  }

  void _setPreview(bool preview) {
    if (_preview == preview) return;
    _bodyFocus.unfocus();
    if (preview) _saveNow();
    setState(() => _preview = preview);
  }

  /// Picks a photo, stores it privately and inserts a Markdown reference.
  Future<void> _pickImage() async {
    _bodyFocus.unfocus();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildImageSourceSheet(),
    );
    if (source == null || !mounted) return;

    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      final file = await AttachmentStore.instance.save(
        picked,
        noteId: _note.id,
      );
      if (!mounted) return;
      _insertImage(file);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('图片插入失败', style: TextStyle(fontSize: 13)),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  void _insertImage(File file) {
    final relative = AttachmentStore.instance.relativePath(file);
    final value = _bodyCtrl.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final text = value.text;
    final start = selection.start;
    final leading = start > 0 && text[start - 1] != '\n' ? '\n' : '';
    final trailing = text.startsWith('\n\n', start) ? '' : '\n\n';
    final insert = '$leading![]($relative)$trailing';

    _bodyCtrl.value = TextEditingValue(
      text: text.replaceRange(start, selection.end, insert),
      selection: TextSelection.collapsed(offset: start + insert.length),
    );
    _saveNow();
    NotesDb.instance.addAttachment(
      id: newAttachmentId(),
      noteId: _note.id,
      relativePath: relative,
      mime: AttachmentStore.instance.mimeOf(file),
      byteSize: file.lengthSync(),
    );
    _bodyFocus.requestFocus();
  }

  Widget _buildImageSourceSheet() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppColors.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: Icon(
                Icons.photo_library_outlined,
                color: AppColors.muted,
              ),
              title: Text(
                '从相册选择',
                style: TextStyle(fontSize: 15, color: AppColors.ink),
              ),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: Icon(
                Icons.photo_camera_outlined,
                color: AppColors.muted,
              ),
              title: Text(
                '拍照',
                style: TextStyle(fontSize: 15, color: AppColors.ink),
              ),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Covers the system back gesture, which does not go through _pop().
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _saveNow();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          backgroundColor: AppColors.bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
            color: AppColors.ink,
            onPressed: _pop,
          ),
          titleSpacing: 0,
          // A single toggle in the bar instead of a mode row in the toolbar:
          // it names the mode you are switching *to*.
          title: Row(
            children: [
              _ModeSwitch(
                preview: _preview,
                onTap: () => _setPreview(!_preview),
              ),
              const Spacer(),
              ValueListenableBuilder<String>(
                valueListenable: _status,
                builder: (context, value, _) {
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: value.isEmpty
                        ? const SizedBox(width: 1, height: 1)
                        : Row(
                            key: ValueKey(value),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: AppColors.accent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                value,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.muted,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                  );
                },
              ),
              const SizedBox(width: 4),
            ],
          ),
          actions: [
            TextButton(
              onPressed: _pop,
              child: Text(
                '完成',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accent,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              // Title and tags scroll together with the body, like the
              // read-only detail page.
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_preview)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          _titleCtrl.text.isEmpty ? '无标题' : _titleCtrl.text,
                          style: _titleStyle,
                        ),
                      )
                    else
                      TextField(
                        controller: _titleCtrl,
                        maxLines: null,
                        textInputAction: TextInputAction.next,
                        style: _titleStyle,
                        decoration: InputDecoration(
                          hintText: '标题',
                          hintStyle: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w600,
                            color: AppColors.muted,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.only(top: 8, bottom: 8),
                        ),
                      ),
                    Container(height: 1, color: AppColors.line),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tag in _tags)
                          TagChip(
                            label: tag.name,
                            colorValue: tag.color,
                            onTap: _editTags,
                          ),
                        TagChip(label: '＋ 添加标签', onTap: _editTags),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (_preview)
                      MarkdownView(
                        source: _bodyCtrl.text,
                        onToggleTask: _togglePreviewTask,
                      )
                    else
                      // Tapping the blank space under the text still focuses
                      // the body field.
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _bodyFocus.requestFocus,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 280),
                          child: TextField(
                            controller: _bodyCtrl,
                            focusNode: _bodyFocus,
                            maxLines: null,
                            keyboardType: TextInputType.multiline,
                            inputFormatters: const [
                              ListContinuationFormatter(),
                            ],
                            style: _bodyStyle,
                            decoration: InputDecoration(
                              hintText: '开始记录…',
                              hintStyle: TextStyle(
                                fontSize: 15,
                                color: AppColors.muted,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            _buildToolbar(),
          ],
        ),
      ),
    );
  }

  /// A fixed 8×2 grid: two rows of eight, no horizontal scrolling, so every
  /// tool keeps its place while typing.
  Widget _buildToolbar() {
    if (_preview) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: SafeArea(
        top: false,
        child: ValueListenableBuilder<MarkdownFormatState>(
          valueListenable: _format,
          builder: (context, state, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  spacing: 2,
                  children: [
                    _cell(
                      _ToolButton(
                        tooltip: '撤销',
                        active: false,
                        enabled: _canUndo,
                        onTap: _undo,
                        child: const Icon(Icons.undo_rounded, size: 19),
                      ),
                    ),
                    _cell(
                      _ToolButton(
                        tooltip: '重做',
                        active: false,
                        enabled: _canRedo,
                        onTap: _redo,
                        child: const Icon(Icons.redo_rounded, size: 19),
                      ),
                    ),
                    _cell(
                      _ToolButton(
                        tooltip: '标题',
                        active: state.headingLevel > 0,
                        onTap: () => _applyToolbar(_ToolbarTool.heading),
                        child: const Text(
                          'T',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    _cell(
                      _ToolButton(
                        tooltip: '加粗',
                        active: state.bold,
                        onTap: () => _applyToolbar(_ToolbarTool.bold),
                        child: const Text(
                          'B',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    _cell(
                      _ToolButton(
                        tooltip: '斜体',
                        active: state.italic,
                        onTap: () => _applyToolbar(_ToolbarTool.italic),
                        child: const Text(
                          'I',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ),
                    _cell(
                      _ToolButton(
                        tooltip: '删除线',
                        active: state.strike,
                        onTap: () => _applyToolbar(_ToolbarTool.strike),
                        child: const Text(
                          'S',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ),
                    ),
                    _cell(
                      _ToolButton(
                        tooltip: '行内代码',
                        active: state.codeSpan,
                        onTap: () => _applyToolbar(_ToolbarTool.codeSpan),
                        child: const Icon(Icons.code_rounded, size: 18),
                      ),
                    ),
                    _cell(
                      _ToolButton(
                        tooltip: '列表',
                        active: state.inList,
                        onTap: () => _applyToolbar(_ToolbarTool.list),
                        child: const Icon(
                          Icons.format_list_bulleted_rounded,
                          size: 19,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  spacing: 2,
                  children: [
                    _cell(
                      _ToolButton(
                        tooltip: '任务列表',
                        active: state.inTask,
                        onTap: () => _applyToolbar(_ToolbarTool.task),
                        child: const Icon(Icons.checklist_rounded, size: 19),
                      ),
                    ),
                    _cell(
                      _ToolButton(
                        tooltip: '缩进',
                        active: false,
                        onTap: () => _applyToolbar(_ToolbarTool.indent),
                        child: const Icon(
                          Icons.format_indent_increase_rounded,
                          size: 19,
                        ),
                      ),
                    ),
                    _cell(
                      _ToolButton(
                        tooltip: '取消缩进',
                        active: false,
                        onTap: () => _applyToolbar(_ToolbarTool.outdent),
                        child: const Icon(
                          Icons.format_indent_decrease_rounded,
                          size: 19,
                        ),
                      ),
                    ),
                    _cell(
                      _ToolButton(
                        tooltip: '代码块',
                        active: state.inCodeBlock,
                        onTap: () => _applyToolbar(_ToolbarTool.code),
                        child: const Icon(Icons.data_object_rounded, size: 19),
                      ),
                    ),
                    _cell(
                      _ToolButton(
                        tooltip: '表格',
                        active: false,
                        onTap: () => _applyToolbar(_ToolbarTool.table),
                        child: const Icon(Icons.table_chart_outlined, size: 19),
                      ),
                    ),
                    _cell(
                      _ToolButton(
                        tooltip: '分隔线',
                        active: false,
                        onTap: () => _applyToolbar(_ToolbarTool.divider),
                        child: const Icon(
                          Icons.horizontal_rule_rounded,
                          size: 20,
                        ),
                      ),
                    ),
                    _cell(
                      _ToolButton(
                        tooltip: '插入图片',
                        active: false,
                        onTap: () => _applyToolbar(_ToolbarTool.image),
                        child: const Icon(Icons.image_outlined, size: 19),
                      ),
                    ),
                    _cell(
                      _ToolButton(
                        tooltip: '插入链接',
                        active: false,
                        onTap: () => _applyToolbar(_ToolbarTool.link),
                        child: const Icon(Icons.link_rounded, size: 19),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _cell(Widget child) => Expanded(child: child);

  TextStyle get _titleStyle => TextStyle(
    fontSize: 21,
    fontWeight: FontWeight.w600,
    height: 1.4,
    letterSpacing: -0.4,
    color: AppColors.ink,
  );

  TextStyle get _bodyStyle => TextStyle(
    fontSize: 15 * AppSettings.instance.bodyScale,
    height: 1.82,
    letterSpacing: 0.1,
    color: AppColors.ink2,
  );
}

enum _ToolbarTool {
  heading,
  list,
  task,
  indent,
  outdent,
  code,
  codeSpan,
  bold,
  italic,
  strike,
  table,
  divider,
  image,
  link,
}

/// One undo step: title and body captured together (F-16).
class _EditorSnapshot {
  const _EditorSnapshot(this.title, this.body);

  final String title;
  final String body;

  bool sameAs(_EditorSnapshot other) =>
      title == other.title && body == other.body;
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.tooltip,
    required this.active,
    required this.onTap,
    required this.child,
    this.enabled = true,
  });

  final String tooltip;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? AppColors.muted.withValues(alpha: 0.4)
        : (active ? AppColors.accentInk : AppColors.ink2);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 38,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            // A tint alone disappears in dark mode, where the soft accent sits
            // almost on top of the surface colour. The hairline keeps the lit
            // state readable in both themes.
            border: Border.all(
              color: active
                  ? AppColors.accent.withValues(alpha: 0.55)
                  : Colors.transparent,
            ),
          ),
          child: IconTheme.merge(
            data: IconThemeData(color: color),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: color),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// One button that flips between editing and reading.
///
/// It is labelled with the mode you get by tapping it, so the label is the
/// action rather than the current state.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.preview, required this.onTap});

  final bool preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = preview ? AppColors.accentInk : AppColors.ink2;
    return Tooltip(
      message: preview ? '切换到编辑' : '切换到预览',
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 29,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: preview ? AppColors.accentSoft : AppColors.bg,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: preview ? Colors.transparent : AppColors.line,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                preview ? Icons.edit_outlined : Icons.visibility_outlined,
                size: 15,
                color: foreground,
              ),
              const SizedBox(width: 5),
              Text(
                preview ? '编辑' : '预览',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: preview ? FontWeight.w600 : FontWeight.w500,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
