/// Minimal Markdown subset used by the note detail view.
///
/// The supported syntax mirrors the editor toolbar (decisions D-1 / D-2):
/// H1-H3 headings, bullet and ordered lists, fenced code blocks, quotes,
/// bold, italic, inline code, links and image references. No underline.
sealed class MdBlock {
  const MdBlock();
}

class MdHeading extends MdBlock {
  const MdHeading(this.level, this.children);

  final int level;
  final List<MdInline> children;
}

class MdParagraph extends MdBlock {
  const MdParagraph(this.children);

  final List<MdInline> children;
}

class MdListBlock extends MdBlock {
  const MdListBlock({required this.ordered, required this.items});

  final bool ordered;
  final List<MdListItem> items;
}

class MdListItem {
  const MdListItem({required this.children, required this.indent, this.number});

  final List<MdInline> children;
  final int indent;
  final int? number;
}

class MdCodeBlock extends MdBlock {
  const MdCodeBlock({required this.code, this.language});

  final String code;
  final String? language;
}

class MdQuote extends MdBlock {
  const MdQuote(this.children);

  final List<MdInline> children;
}

sealed class MdInline {
  const MdInline();
}

class MdText extends MdInline {
  const MdText(this.text);

  final String text;
}

class MdStrong extends MdInline {
  const MdStrong(this.children);

  final List<MdInline> children;
}

class MdEmphasis extends MdInline {
  const MdEmphasis(this.children);

  final List<MdInline> children;
}

class MdCodeSpan extends MdInline {
  const MdCodeSpan(this.code);

  final String code;
}

class MdLink extends MdInline {
  const MdLink({required this.label, required this.url});

  final List<MdInline> label;
  final String url;
}

class MdImage extends MdInline {
  const MdImage({required this.alt, required this.url});

  final String alt;
  final String url;
}

class MdDocument {
  const MdDocument(this.blocks);

  final List<MdBlock> blocks;

  bool get isEmpty => blocks.isEmpty;
}

final RegExp _headingPattern = RegExp(r'^(#{1,6})\s+(.*)$');
final RegExp _fencePattern = RegExp(r'^\s*```(.*)$');
final RegExp _quotePattern = RegExp(r'^\s*>\s?(.*)$');
final RegExp _listPattern = RegExp(r'^(\s*)([-*+]|\d+[.)])\s+(.*)$');

/// A line holding nothing but an image reference, e.g. `![](attachments/a.jpg)`.
///
/// Such a line is its own block even without a surrounding blank line, so the
/// image inserted right after a paragraph still renders as a picture (F-14).
final RegExp _imageLinePattern = RegExp(r'^!\[[^\]]*\]\([^)]*\)$');

MdDocument parseMarkdown(String source) {
  final lines = source
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  final blocks = <MdBlock>[];
  var index = 0;

  while (index < lines.length) {
    final line = lines[index];
    if (line.trim().isEmpty) {
      index++;
      continue;
    }

    final fence = _fencePattern.firstMatch(line);
    if (fence != null) {
      final language = fence.group(1)!.trim();
      final buffer = StringBuffer();
      index++;
      while (index < lines.length && !_fencePattern.hasMatch(lines[index])) {
        if (buffer.isNotEmpty) buffer.write('\n');
        buffer.write(lines[index]);
        index++;
      }
      // Skip the closing fence when present; an unclosed block runs to EOF.
      if (index < lines.length) index++;
      blocks.add(
        MdCodeBlock(
          code: buffer.toString(),
          language: language.isEmpty ? null : language,
        ),
      );
      continue;
    }

    final heading = _headingPattern.firstMatch(line);
    if (heading != null) {
      final rawLevel = heading.group(1)!.length;
      final level = rawLevel > 3 ? 3 : rawLevel;
      final text = heading
          .group(2)!
          .replaceFirst(RegExp(r'\s+#+\s*$'), '')
          .trim();
      blocks.add(MdHeading(level, _parseInline(text)));
      index++;
      continue;
    }

    if (_quotePattern.hasMatch(line)) {
      final quoted = <String>[];
      while (index < lines.length) {
        final match = _quotePattern.firstMatch(lines[index]);
        if (match == null) break;
        quoted.add(match.group(1)!);
        index++;
      }
      blocks.add(MdQuote(_parseInline(quoted.join('\n'))));
      continue;
    }

    final listMatch = _listPattern.firstMatch(line);
    if (listMatch != null) {
      final ordered = !RegExp(r'^[-*+]$').hasMatch(listMatch.group(2)!);
      final items = <MdListItem>[];
      while (index < lines.length) {
        final match = _listPattern.firstMatch(lines[index]);
        if (match == null) break;
        final marker = match.group(2)!;
        final isOrdered = !RegExp(r'^[-*+]$').hasMatch(marker);
        if (isOrdered != ordered) break;
        final indent = match.group(1)!.length;
        items.add(
          MdListItem(
            children: _parseInline(match.group(3)!.trim()),
            indent: indent >= 2 ? 1 : 0,
            number: ordered
                ? int.tryParse(marker.replaceAll(RegExp(r'[.)]$'), ''))
                : null,
          ),
        );
        index++;
      }
      blocks.add(MdListBlock(ordered: ordered, items: items));
      continue;
    }

    if (_imageLinePattern.hasMatch(line.trim())) {
      blocks.add(MdParagraph(_parseInline(line.trim())));
      index++;
      continue;
    }

    final paragraph = <String>[];
    while (index < lines.length) {
      final current = lines[index];
      if (current.trim().isEmpty || _startsBlock(current)) break;
      paragraph.add(current.trim());
      index++;
    }
    if (paragraph.isNotEmpty) {
      blocks.add(MdParagraph(_parseInline(paragraph.join('\n'))));
    }
  }

  return MdDocument(blocks);
}

/// A heading shown in the reading outline (F-57).
class MdOutlineEntry {
  const MdOutlineEntry({
    required this.blockIndex,
    required this.level,
    required this.text,
  });

  /// Index of the heading inside [MdDocument.blocks].
  final int blockIndex;
  final int level;
  final String text;
}

/// Collects H1-H3 headings in document order (F-57).
List<MdOutlineEntry> extractOutline(MdDocument document) {
  final entries = <MdOutlineEntry>[];
  for (var index = 0; index < document.blocks.length; index++) {
    final block = document.blocks[index];
    if (block is! MdHeading) continue;
    final text = inlinePlainText(block.children).trim();
    if (text.isEmpty) continue;
    entries.add(
      MdOutlineEntry(blockIndex: index, level: block.level, text: text),
    );
  }
  return entries;
}

/// Visible text of inline nodes, without any Markdown markers.
String inlinePlainText(List<MdInline> inline) {
  final buffer = StringBuffer();
  for (final item in inline) {
    switch (item) {
      case MdText(:final text):
        buffer.write(text);
      case MdStrong(:final children):
        buffer.write(inlinePlainText(children));
      case MdEmphasis(:final children):
        buffer.write(inlinePlainText(children));
      case MdCodeSpan(:final code):
        buffer.write(code);
      case MdLink(:final label):
        buffer.write(inlinePlainText(label));
      case MdImage(:final alt):
        buffer.write(alt);
    }
  }
  return buffer.toString();
}

/// Visible text of a whole block, used to locate a search hit (F-28).
String blockPlainText(MdBlock block) {
  return switch (block) {
    MdHeading(:final children) => inlinePlainText(children),
    MdParagraph(:final children) => inlinePlainText(children),
    MdListBlock(:final items) => items
        .map((item) => inlinePlainText(item.children))
        .join('\n'),
    MdCodeBlock(:final code) => code,
    MdQuote(:final children) => inlinePlainText(children),
  };
}

/// Index of the first block containing [keyword], or null when absent (F-28).
int? firstMatchBlock(MdDocument document, String keyword) {
  final lower = keyword.trim().toLowerCase();
  if (lower.isEmpty) return null;
  for (var index = 0; index < document.blocks.length; index++) {
    if (blockPlainText(document.blocks[index]).toLowerCase().contains(lower)) {
      return index;
    }
  }
  return null;
}

bool _startsBlock(String line) {
  return _fencePattern.hasMatch(line) ||
      _headingPattern.hasMatch(line) ||
      _quotePattern.hasMatch(line) ||
      _listPattern.hasMatch(line) ||
      _imageLinePattern.hasMatch(line.trim());
}

List<MdInline> _parseInline(String text) {
  final spans = <MdInline>[];
  final buffer = StringBuffer();
  var index = 0;

  void flush() {
    if (buffer.isEmpty) return;
    spans.add(MdText(buffer.toString()));
    buffer.clear();
  }

  while (index < text.length) {
    final char = text[index];

    if (char == r'\' && index + 1 < text.length) {
      buffer.write(text[index + 1]);
      index += 2;
      continue;
    }

    if (char == '`') {
      final end = text.indexOf('`', index + 1);
      if (end != -1) {
        flush();
        spans.add(MdCodeSpan(text.substring(index + 1, end)));
        index = end + 1;
        continue;
      }
    }

    if (char == '!' && index + 1 < text.length && text[index + 1] == '[') {
      final match = _imagePattern.matchAsPrefix(text, index);
      if (match != null) {
        flush();
        spans.add(MdImage(alt: match.group(1)!, url: match.group(2)!));
        index = match.end;
        continue;
      }
    }

    if (char == '[') {
      final match = _linkPattern.matchAsPrefix(text, index);
      if (match != null) {
        flush();
        spans.add(
          MdLink(label: _parseInline(match.group(1)!), url: match.group(2)!),
        );
        index = match.end;
        continue;
      }
    }

    if (text.startsWith('**', index)) {
      final end = text.indexOf('**', index + 2);
      if (end != -1 && end > index + 2) {
        flush();
        spans.add(MdStrong(_parseInline(text.substring(index + 2, end))));
        index = end + 2;
        continue;
      }
    }

    if (char == '*') {
      final end = text.indexOf('*', index + 1);
      if (end != -1 && end > index + 1) {
        flush();
        spans.add(MdEmphasis(_parseInline(text.substring(index + 1, end))));
        index = end + 1;
        continue;
      }
    }

    buffer.write(char);
    index++;
  }

  flush();
  return spans;
}

final RegExp _linkPattern = RegExp(r'\[([^\]]*)\]\(([^)]*)\)');
final RegExp _imagePattern = RegExp(r'!\[([^\]]*)\]\(([^)]*)\)');
