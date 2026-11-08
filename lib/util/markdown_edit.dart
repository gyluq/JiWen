import 'package:flutter/services.dart';

/// Pure text transforms used by the editor toolbar.
///
/// The app edits Markdown source directly (decision D-1), so every toolbar
/// action rewrites the text value and reports where the caret should land.
class MarkdownEdit {
  const MarkdownEdit({required this.text, required this.selection});

  final String text;
  final TextSelection selection;

  TextEditingValue get value =>
      TextEditingValue(text: text, selection: selection);
}

/// Formatting state at the caret; drives the highlighted toolbar buttons.
class MarkdownFormatState {
  const MarkdownFormatState({
    this.headingLevel = 0,
    this.inList = false,
    this.inCodeBlock = false,
    this.bold = false,
    this.italic = false,
  });

  final int headingLevel;
  final bool inList;
  final bool inCodeBlock;
  final bool bold;
  final bool italic;
}

final RegExp _headingPrefix = RegExp(r'^(#{1,6})\s+');
final RegExp _listMarker = RegExp(r'^(\s*)([-*+]|\d+[.)])\s+');
final RegExp _orderedItem = RegExp(r'^(\s*)(\d+)([.)])\s+(.*)$');
final RegExp _bulletItem = RegExp(r'^(\s*)([-*+])\s+(.*)$');

MarkdownEdit toggleBold(TextEditingValue value) =>
    _toggleInline(value, '**', '粗体');

MarkdownEdit toggleItalic(TextEditingValue value) =>
    _toggleInline(value, '*', '斜体');

/// Cycles the current line(s) through H1, H2, H3 and no heading.
MarkdownEdit cycleHeading(TextEditingValue value) {
  final text = value.text;
  final selection = _selectionOf(value);
  final span = _lineSpan(text, selection);
  final lines = text.substring(span.start, span.end).split('\n');
  final current = _headingLevel(lines.first);
  final next = current >= 3 ? 0 : current + 1;
  final edits = <_Edit>[];
  var offset = span.start;

  for (final line in lines) {
    final match = _headingPrefix.firstMatch(line);
    final prefixLength = match?.end ?? 0;
    final replacement = next == 0 ? '' : '${'#' * next} ';
    edits.add(_Edit(offset, offset + prefixLength, replacement));
    offset += line.length + 1;
  }
  return _result(text, edits, selection);
}

/// Toggles a bullet list on the selected lines.
MarkdownEdit toggleList(TextEditingValue value) {
  final text = value.text;
  final selection = _selectionOf(value);
  final span = _lineSpan(text, selection);
  final lines = text.substring(span.start, span.end).split('\n');
  final hasMarker = lines.any((line) => _listMarker.hasMatch(line));
  final allMarked =
      hasMarker &&
      lines.every((line) => line.trim().isEmpty || _listMarker.hasMatch(line));
  final edits = <_Edit>[];
  var offset = span.start;
  var hasContent = false;

  for (final line in lines) {
    if (line.trim().isNotEmpty) hasContent = true;
  }

  for (final line in lines) {
    final match = _listMarker.firstMatch(line);
    if (allMarked) {
      if (match != null) {
        edits.add(_Edit(offset + match.start, offset + match.end, ''));
      }
    } else if (line.trim().isNotEmpty) {
      final indent = line.length - line.trimLeft().length;
      edits.add(_Edit(offset + indent, offset + indent, '- '));
    }
    offset += line.length + 1;
  }
  // A single blank line still receives a marker so the user can start typing.
  if (!allMarked && !hasContent) {
    final indent = lines.first.length - lines.first.trimLeft().length;
    edits.add(_Edit(span.start + indent, span.start + indent, '- '));
  }
  return _result(text, edits, selection);
}

/// Wraps the current lines in a fenced code block, or removes the fences when
/// the caret already sits inside a closed block.
MarkdownEdit toggleCodeBlock(TextEditingValue value) {
  final text = value.text;
  final selection = _selectionOf(value);
  final span = _lineSpan(text, selection);
  final starts = _lineStarts(text);
  final first = _lineIndexAt(starts, span.start);

  var fencesBefore = 0;
  for (var i = 0; i < first; i++) {
    if (_isFence(_lineText(text, starts, i))) fencesBefore++;
  }

  if (fencesBefore.isOdd) {
    var open = -1;
    for (var i = first - 1; i >= 0; i--) {
      if (_isFence(_lineText(text, starts, i))) {
        open = i;
        break;
      }
    }
    var close = -1;
    for (var i = first; i < starts.length; i++) {
      if (_isFence(_lineText(text, starts, i))) {
        close = i;
        break;
      }
    }
    if (open != -1 && close != -1) {
      final openEnd = starts[open + 1];
      final closeEnd = close + 1 < starts.length
          ? starts[close + 1]
          : text.length;
      // A closing fence on the last line takes the newline before it along,
      // so blocks at the end of the note do not leave a blank line behind.
      final closeStart = close + 1 < starts.length
          ? starts[close]
          : starts[close] - 1;
      final edits = closeStart < openEnd
          ? [_Edit(starts[open], closeEnd, '')]
          : [_Edit(starts[open], openEnd, ''), _Edit(closeStart, closeEnd, '')];
      return _result(text, edits, selection);
    }
  }

  // Wrap the selected lines; an empty line gets a blank code body.
  final edits = <_Edit>[];
  if (span.start == span.end) {
    edits.add(_Edit(span.start, span.end, '```\n\n```'));
    final caret = span.start + 4;
    return MarkdownEdit(
      text: _applyEdits(text, edits),
      selection: TextSelection.collapsed(offset: caret),
    );
  }

  final needsNewline = span.end < text.length && text[span.end] != '\n';
  edits.add(_Edit(span.start, span.start, '```\n'));
  edits.add(_Edit(span.end, span.end, needsNewline ? '\n```\n' : '\n```'));
  return MarkdownEdit(
    text: _applyEdits(text, edits),
    selection: TextSelection(
      baseOffset: selection.start + 4,
      extentOffset: selection.end + 4,
    ),
  );
}

/// Inserts `[label](url)`, selecting the URL so a paste replaces it.
MarkdownEdit insertLink(TextEditingValue value) {
  final text = value.text;
  final selection = _selectionOf(value);
  final start = selection.start;
  final end = selection.end;
  final selected = text.substring(start, end);

  final label = selected.isEmpty ? '链接文字' : selected;
  final insert = '[$label](https://)';
  final urlStart = start + 1 + label.length + 2;
  final newText = text.replaceRange(start, end, insert);
  return MarkdownEdit(
    text: newText,
    selection: TextSelection(
      baseOffset: urlStart,
      extentOffset: urlStart + 'https://'.length,
    ),
  );
}

/// Reads the format state at the caret for the toolbar highlight.
MarkdownFormatState inspectMarkdown(TextEditingValue value) {
  final text = value.text;
  final selection = _selectionOf(value);
  final offset = selection.start;
  final lineStart = offset > 0 ? text.lastIndexOf('\n', offset - 1) + 1 : 0;
  final lineEnd = text.indexOf('\n', offset);
  final line = text.substring(lineStart, lineEnd == -1 ? text.length : lineEnd);

  final heading = _headingPrefix.firstMatch(line);
  final headingLevel = heading == null ? 0 : heading.group(1)!.length;

  var fences = 0;
  final prefix = text.substring(0, lineStart);
  for (final prefixLine in prefix.split('\n')) {
    if (prefixLine.trimLeft().startsWith('```')) fences++;
  }

  var bold = false;
  var italic = false;
  var index = lineStart;
  while (index < offset) {
    if (text.startsWith('**', index)) {
      bold = !bold;
      index += 2;
    } else if (text[index] == '*') {
      italic = !italic;
      index++;
    } else {
      index++;
    }
  }
  final rest = text.substring(offset, lineEnd == -1 ? text.length : lineEnd);
  bold = bold && rest.contains('**');
  italic = italic && rest.contains('*');

  return MarkdownFormatState(
    headingLevel: headingLevel,
    inList: _listMarker.hasMatch(line),
    inCodeBlock: fences.isOdd,
    bold: bold,
    italic: italic,
  );
}

/// Continues bullet and ordered lists on Enter; a second Enter exits the list.
class ListContinuationFormatter extends TextInputFormatter {
  const ListContinuationFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final oldText = oldValue.text;
    final newText = newValue.text;
    if (newText.length != oldText.length + 1) return newValue;
    if (!newValue.selection.isCollapsed) return newValue;

    var index = 0;
    while (index < oldText.length && oldText[index] == newText[index]) {
      index++;
    }
    if (index >= newText.length || newText[index] != '\n') return newValue;
    final tailMatches = newText.substring(index + 1) == oldText.substring(index);
    if (!tailMatches) return newValue;
    if (newValue.selection.start != index + 1) return newValue;

    final lineStart = index > 0 ? oldText.lastIndexOf('\n', index - 1) + 1 : 0;
    final line = oldText.substring(lineStart, index);
    if (line.isEmpty) return newValue;

    final bullet = _bulletItem.firstMatch(line);
    final ordered = _orderedItem.firstMatch(line);
    if (bullet == null && ordered == null) return newValue;

    final match = bullet ?? ordered!;
    final indent = match.group(1)!;

    if (match.group(match.groupCount)!.trim().isEmpty) {
      // Empty item: drop the marker and keep the pressed newline.
      final markerStart = lineStart + indent.length;
      final text =
          '${oldText.substring(0, markerStart)}\n'
          '${oldText.substring(index)}';
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: markerStart),
      );
    }

    final String marker;
    if (bullet != null) {
      marker = bullet.group(2)!;
    } else {
      final number = int.parse(ordered!.group(2)!);
      marker = '${number + 1}${ordered.group(3)}';
    }
    final continuation = '\n$indent$marker ';
    final text =
        '${oldText.substring(0, index)}$continuation'
        '${oldText.substring(index)}';
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: index + continuation.length),
    );
  }
}

// ---------------------------------------------------------------------------
// Internals

class _Edit {
  const _Edit(this.start, this.end, this.replacement);

  final int start;
  final int end;
  final String replacement;
}

class _LineSpan {
  const _LineSpan(this.start, this.end);

  final int start;
  final int end;
}

TextSelection _selectionOf(TextEditingValue value) {
  final selection = value.selection;
  if (selection.isValid) return selection;
  return TextSelection.collapsed(offset: value.text.length);
}

MarkdownEdit _result(String text, List<_Edit> edits, TextSelection selection) {
  return MarkdownEdit(
    text: _applyEdits(text, edits),
    selection: TextSelection(
      baseOffset: _mapOffset(edits, selection.start),
      extentOffset: _mapOffset(edits, selection.end),
    ),
  );
}

String _applyEdits(String text, List<_Edit> edits) {
  final sorted = edits.toList()..sort((a, b) => b.start.compareTo(a.start));
  var result = text;
  for (final edit in sorted) {
    result = result.replaceRange(edit.start, edit.end, edit.replacement);
  }
  return result;
}

int _mapOffset(List<_Edit> edits, int offset) {
  var delta = 0;
  for (final edit in edits) {
    final removed = edit.end - edit.start;
    final added = edit.replacement.length;
    if (offset >= edit.end) {
      delta += added - removed;
    } else if (offset > edit.start) {
      delta += edit.start + added - offset;
    }
  }
  final mapped = offset + delta;
  return mapped < 0 ? 0 : mapped;
}

_LineSpan _lineSpan(String text, TextSelection selection) {
  final start = selection.start;
  // A selection ending exactly at a line start does not include that line.
  var end = selection.end;
  if (end > start && end > 0 && text[end - 1] == '\n') end -= 1;

  final lineStart = start > 0 ? text.lastIndexOf('\n', start - 1) + 1 : 0;
  var lineEnd = text.indexOf('\n', end);
  if (lineEnd == -1) lineEnd = text.length;
  return _LineSpan(lineStart, lineEnd);
}

List<int> _lineStarts(String text) {
  final starts = <int>[0];
  for (var i = 0; i < text.length; i++) {
    if (text[i] == '\n') starts.add(i + 1);
  }
  return starts;
}

int _lineIndexAt(List<int> starts, int offset) {
  var index = 0;
  for (var i = 0; i < starts.length; i++) {
    if (starts[i] <= offset) {
      index = i;
    } else {
      break;
    }
  }
  return index;
}

String _lineText(String text, List<int> starts, int index) {
  final start = starts[index];
  final end = index + 1 < starts.length ? starts[index + 1] - 1 : text.length;
  return text.substring(start, end);
}

bool _isFence(String line) => line.trimLeft().startsWith('```');

int _headingLevel(String line) {
  final match = _headingPrefix.firstMatch(line);
  return match == null ? 0 : match.group(1)!.length;
}

MarkdownEdit _toggleInline(
  TextEditingValue value,
  String marker,
  String placeholder,
) {
  final text = value.text;
  final selection = _selectionOf(value);
  final start = selection.start;
  final end = selection.end;
  final selected = text.substring(start, end);

  bool markerAt(int index) =>
      index >= 0 &&
      index + marker.length <= text.length &&
      text.substring(index, index + marker.length) == marker;

  // Italic must not consume one of the two asterisks of a bold marker.
  bool conflictsAt(int index) =>
      marker == '*' &&
      ((index > 0 && text[index - 1] == '*') ||
          (index + 1 < text.length && text[index + 1] == '*'));

  final surrounded =
      markerAt(start - marker.length) &&
      markerAt(end) &&
      !conflictsAt(start - marker.length) &&
      !conflictsAt(end);

  if (surrounded) {
    final edits = [
      _Edit(start - marker.length, start, ''),
      _Edit(end, end + marker.length, ''),
    ];
    return MarkdownEdit(
      text: _applyEdits(text, edits),
      selection: TextSelection(
        baseOffset: start - marker.length,
        extentOffset: end - marker.length,
      ),
    );
  }

  final wrappedInSelection =
      selected.length >= marker.length * 2 &&
      selected.startsWith(marker) &&
      selected.endsWith(marker) &&
      !(marker == '*' && selected.startsWith('**'));

  if (wrappedInSelection) {
    final newText = text.replaceRange(
      start,
      end,
      selected.substring(marker.length, selected.length - marker.length),
    );
    final innerLength = selected.length - marker.length * 2;
    return MarkdownEdit(
      text: newText,
      selection: TextSelection(
        baseOffset: start,
        extentOffset: start + innerLength,
      ),
    );
  }

  if (selected.isEmpty) {
    final insert = '$marker$placeholder$marker';
    return MarkdownEdit(
      text: text.replaceRange(start, end, insert),
      selection: TextSelection(
        baseOffset: start + marker.length,
        extentOffset: start + marker.length + placeholder.length,
      ),
    );
  }

  return MarkdownEdit(
    text: text.replaceRange(start, end, '$marker$selected$marker'),
    selection: TextSelection(
      baseOffset: start + marker.length,
      extentOffset: end + marker.length,
    ),
  );
}
