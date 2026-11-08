import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/note.dart';
import '../models/tag.dart';
import 'attachments.dart';
import 'notes_db.dart';

/// Produces the Markdown and ZIP exports of F-36 / F-37.
///
/// Files are written into the cache so the share sheet can pick them up;
/// nothing is written to public storage.
class NoteExporter {
  NoteExporter._();
  static final NoteExporter instance = NoteExporter._();

  Future<Directory> _exportDir() async {
    final cache = await getTemporaryDirectory();
    final dir = Directory(p.join(cache.path, 'exports'));
    await dir.create(recursive: true);
    return dir;
  }

  /// Single-note Markdown document (F-36).
  ///
  /// Front matter carries the title, tags and timestamps; the body follows
  /// unchanged so the result opens cleanly in Obsidian or any editor.
  String markdownFor(
    Note note, {
    List<Tag> tags = const [],
    bool rewriteAssets = false,
  }) {
    final buffer = StringBuffer('---\n');
    buffer.writeln(
      'title: ${jsonEncode(note.title.trim().isEmpty ? '无标题' : note.title.trim())}',
    );
    buffer.writeln('created: ${_timestamp(note.createdAt)}');
    buffer.writeln('updated: ${_timestamp(note.updatedAt)}');
    buffer.writeln('status: ${note.status == NoteStatus.done ? '已解答' : '待解答'}');
    if (tags.isNotEmpty) {
      buffer.writeln(
        'tags: [${tags.map((tag) => jsonEncode(tag.name)).join(', ')}]',
      );
    }
    buffer.writeln('---');
    buffer.writeln();
    final title = note.title.trim();
    if (title.isNotEmpty) {
      buffer.writeln('# $title');
      buffer.writeln();
    }
    final body = rewriteAssets
        ? note.body.replaceAll('attachments/', 'assets/')
        : note.body;
    buffer.write(body);
    if (!body.endsWith('\n')) buffer.writeln();
    return buffer.toString();
  }

  /// Writes one note as `<title>.md` and returns the file to share.
  Future<File> exportSingle(Note note) async {
    final dir = await _exportDir();
    final tags = NotesDb.instance.tagsOfNote(note.id);
    final file = File(p.join(dir.path, '${_baseName(note.title, note.id)}.md'));
    await file.writeAsString(markdownFor(note, tags: tags));
    return file;
  }

  /// Builds the full ZIP: one Markdown file per live note plus `assets/`
  /// holding every referenced image (F-37).
  Future<File> exportAllZip() async {
    final db = NotesDb.instance;
    final notes = db
        .allNotesForBackup()
        .where((note) => note.deletedAt == null)
        .toList();
    final tagsByNote = db.tagsOfNotes(notes.map((note) => note.id));
    final attachments = db.attachmentsOfNotes(notes.map((note) => note.id));

    final archive = Archive();
    final usedNames = <String>{};
    final addedAssets = <String>{};

    for (final row in attachments) {
      final relative = row['relative_path'] as String?;
      if (relative == null || relative.isEmpty) continue;
      final name = p.basename(relative);
      if (!addedAssets.add(name)) continue;
      final file = AttachmentStore.instance.resolve(relative);
      if (file == null || !file.existsSync()) continue;
      try {
        final bytes = await file.readAsBytes();
        archive.addFile(ArchiveFile('assets/$name', bytes.length, bytes));
      } on FileSystemException {
        // A missing image must not abort the whole export.
      }
    }

    for (final note in notes) {
      final content = markdownFor(
        note,
        tags: tagsByNote[note.id] ?? const [],
        rewriteAssets: true,
      );
      final bytes = utf8.encode(content);
      final name = _uniqueName(_baseName(note.title, note.id), usedNames);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    final encoded = ZipEncoder().encodeBytes(archive);
    final dir = await _exportDir();
    final file = File(
      p.join(dir.path, 'jiwen_export_${_fileStamp(DateTime.now())}.zip'),
    );
    await file.writeAsBytes(encoded);
    return file;
  }

  /// File name safe on Android and on the desktop systems Obsidian runs on.
  String _baseName(String title, String id) {
    var name = title.trim();
    name = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ');
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (name.isEmpty) name = '无标题';
    if (name.length > 60) name = name.substring(0, 60).trim();
    return name;
  }

  /// Two notes sharing a title must not overwrite each other (F-37).
  String _uniqueName(String base, Set<String> used) {
    var candidate = '$base.md';
    var index = 2;
    while (used.contains(candidate.toLowerCase())) {
      candidate = '$base ($index).md';
      index++;
    }
    used.add(candidate.toLowerCase());
    return candidate;
  }

  static String _timestamp(int millis) {
    final time = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${time.year.toString().padLeft(4, '0')}-'
        '${time.month.toString().padLeft(2, '0')}-'
        '${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  static String _fileStamp(DateTime time) {
    return '${time.year.toString().padLeft(4, '0')}'
        '${time.month.toString().padLeft(2, '0')}'
        '${time.day.toString().padLeft(2, '0')}_'
        '${time.hour.toString().padLeft(2, '0')}'
        '${time.minute.toString().padLeft(2, '0')}'
        '${time.second.toString().padLeft(2, '0')}';
  }
}
