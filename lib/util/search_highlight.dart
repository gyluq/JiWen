import 'dart:math';

/// A run of text that either matches the search keyword or does not.
class SearchRun {
  const SearchRun({required this.text, required this.isHit});

  final String text;
  final bool isHit;
}

/// Splits [text] into alternating plain and matched runs (F-28).
///
/// Matching is case-insensitive and repeated, so every occurrence in the
/// visible snippet gets highlighted.
List<SearchRun> highlightRuns(String text, String query) {
  final keyword = query.trim();
  if (keyword.isEmpty || text.isEmpty) {
    return [SearchRun(text: text, isHit: false)];
  }

  final lowerText = text.toLowerCase();
  final lowerKeyword = keyword.toLowerCase();
  final runs = <SearchRun>[];
  var cursor = 0;
  while (true) {
    final hit = lowerText.indexOf(lowerKeyword, cursor);
    if (hit < 0) break;
    if (hit > cursor) {
      runs.add(SearchRun(text: text.substring(cursor, hit), isHit: false));
    }
    runs.add(
      SearchRun(text: text.substring(hit, hit + keyword.length), isHit: true),
    );
    cursor = hit + keyword.length;
  }
  if (cursor < text.length) {
    runs.add(SearchRun(text: text.substring(cursor), isHit: false));
  }
  return runs.isEmpty ? [SearchRun(text: text, isHit: false)] : runs;
}

/// Converts Markdown source into the plain-text excerpt shown in list rows.
///
/// F-32 defines the snippet as plain text, so image references and link
/// targets must not leak into the list.
String markdownToPlainText(String source) {
  var text = source;
  text = text.replaceAllMapped(
    RegExp(r'!\[([^\]]*)\]\([^)]*\)'),
    (match) => match.group(1)!.trim(),
  );
  text = text.replaceAllMapped(
    RegExp(r'\[([^\]]*)\]\([^)]*\)'),
    (match) => match.group(1)!,
  );
  text = text.replaceAll(RegExp(r'```[^\n]*\n?'), ' ');
  text = text.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^\s*>+\s?', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^\s*(?:-|\*|\+)\s+', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '');
  text = text.replaceAll('**', '');
  text = text.replaceAll('__', '');
  text = text.replaceAll('`', '');
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Builds the excerpt shown in a search result row.
///
/// When the keyword only appears further down the body, the window slides
/// around the first hit so the reader can see why the note matched.
String searchSnippet(String body, String query, {int maxLength = 80}) {
  final flat = markdownToPlainText(body);
  final keyword = query.trim();
  if (flat.length <= maxLength) return flat;
  if (keyword.isEmpty) return '${flat.substring(0, maxLength)}…';

  final hit = flat.toLowerCase().indexOf(keyword.toLowerCase());
  if (hit < 0 || hit + keyword.length <= maxLength) {
    return '${flat.substring(0, maxLength)}…';
  }

  final lead = (maxLength - keyword.length) ~/ 3;
  var start = hit - lead;
  if (start < 0) start = 0;
  var end = start + maxLength;
  if (end > flat.length) {
    end = flat.length;
    start = max(0, end - maxLength);
  }
  final prefix = start > 0 ? '…' : '';
  final suffix = end < flat.length ? '…' : '';
  return '$prefix${flat.substring(start, end)}$suffix';
}
