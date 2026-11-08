/// How pasted text is cut into separate notes (F-40).
enum ImportSeparator {
  blankLines('两个空行'),
  rule('---'),
  custom('自定义');

  const ImportSeparator(this.label);

  final String label;
}

/// Splits a pasted or imported document into note-sized chunks.
///
/// The blank-line rule needs two empty lines between notes (three newlines),
/// so ordinary paragraphs inside one note stay together.
List<String> splitImportText(
  String text,
  ImportSeparator separator, {
  String customDelimiter = '',
}) {
  if (text.trim().isEmpty) return const [];

  final Iterable<String> parts;
  switch (separator) {
    case ImportSeparator.blankLines:
      parts = text.split(RegExp(r'\r?\n{3,}'));
    case ImportSeparator.rule:
      // A line made only of dashes, wherever it sits in the text.
      parts = text.split(RegExp(r'^[ \t]*---[ \t]*$', multiLine: true));
    case ImportSeparator.custom:
      parts = customDelimiter.isEmpty ? [text] : text.split(customDelimiter);
  }

  return parts
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
}

/// Title of a chunk: its first line without any leading Markdown heading.
String importTitleOf(String chunk) {
  final line = chunk.split('\n').first.trim();
  final title = line.replaceFirst(RegExp(r'^#{1,6}\s*'), '').trim();
  if (title.length <= 80) return title;
  return title.substring(0, 80).trim();
}

/// Body of a chunk: everything after the first line.
String importBodyOf(String chunk) {
  final index = chunk.indexOf('\n');
  if (index < 0) return '';
  return chunk.substring(index + 1).trim();
}
