import 'dart:convert';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../models/note.dart';
import '../models/tag.dart';
import '../util/tag_colors.dart';

/// Segments available on the note list (requirement F-05/F-06/R-02).
enum NoteFilter { all, todo, done, pinned }

/// Sort orders offered by the note list (requirement F-25).
enum NoteSort {
  updated('updated'),
  created('created'),
  title('title');

  const NoteSort(this.value);
  final String value;

  static NoteSort fromValue(String? value) {
    return values.firstWhere(
      (sort) => sort.value == value,
      orElse: () => NoteSort.updated,
    );
  }
}

/// Thin synchronous wrapper around the bundled SQLite database.
///
/// The bundled engine is required for Chinese substring search later: the
/// system SQLite on Android 11 has no FTS5 trigram tokenizer.
class NotesDb {
  NotesDb._();
  static final NotesDb instance = NotesDb._();

  Database? _db;
  Database get _database =>
      _db ?? (throw StateError('NotesDb.init() not called'));

  Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    final file = p.join(dir.path, 'jiwen.db');
    final db = sqlite3.open(file);
    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('''
      CREATE TABLE IF NOT EXISTS notes (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL DEFAULT '',
        body TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'todo',
        pinned INTEGER NOT NULL DEFAULT 0,
        favorite INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS tag (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        color INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS note_tag (
        note_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        PRIMARY KEY (note_id, tag_id)
      )
    ''');
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_note_tag_tag ON note_tag(tag_id)',
    );
    db.execute('''
      CREATE TABLE IF NOT EXISTS attachment (
        id TEXT PRIMARY KEY,
        note_id TEXT NOT NULL,
        relative_path TEXT NOT NULL,
        mime TEXT NOT NULL,
        width INTEGER,
        height INTEGER,
        byte_size INTEGER,
        created_at INTEGER NOT NULL
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS setting (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    _db = db;
    _ensureTagColorColumn(db);
  }

  /// Adds the color column to databases created by earlier builds.
  void _ensureTagColorColumn(Database db) {
    final columns = db.select('PRAGMA table_info(tag)');
    final hasColor = columns.any((row) => row['name'] == 'color');
    if (hasColor) return;
    db.execute('ALTER TABLE tag ADD COLUMN color INTEGER NOT NULL DEFAULT 0');
    for (final row in db.select('SELECT id, name FROM tag')) {
      final name = row['name'] as String? ?? '';
      db.execute('UPDATE tag SET color = ? WHERE id = ?', [
        tagColorForName(name),
        row['id'],
      ]);
    }
  }

  /// Lists notes for the current segment, keyword, tag, favorites and the
  /// lower bound of the updated-at range (F-23).
  ///
  /// Keyword matching covers the title, the body and the tag names (F-26).
  /// [updatedSince] is an epoch-millisecond lower bound matched against
  /// `updated_at`.
  ///
  /// Chinese substring search is a LIKE scan. Measured on a Redmi K30:
  /// 5000 notes / ~1.5MB of text scanned in 2-22ms, so a plain scan is
  /// cheaper than maintaining an index. FTS5 trigram cannot match queries
  /// shorter than 3 characters, which rules it out for F-27.
  List<Note> listNotes({
    NoteFilter filter = NoteFilter.all,
    String query = '',
    String? tagId,
    bool favoriteOnly = false,
    int? updatedSince,
    NoteSort sort = NoteSort.updated,
  }) {
    final where = <String>['deleted_at IS NULL'];
    if (filter == NoteFilter.todo) {
      where.add("status = 'todo'");
    } else if (filter == NoteFilter.done) {
      where.add("status = 'done'");
    } else if (filter == NoteFilter.pinned) {
      where.add('pinned = 1');
    }

    final args = <Object?>[];
    if (favoriteOnly) {
      where.add('favorite = 1');
    }
    if (updatedSince != null) {
      where.add('updated_at >= ?');
      args.add(updatedSince);
    }
    if (tagId != null) {
      where.add(
        'EXISTS (SELECT 1 FROM note_tag nt '
        'WHERE nt.note_id = notes.id AND nt.tag_id = ?)',
      );
      args.add(tagId);
    }

    final keyword = query.trim();
    if (keyword.isNotEmpty) {
      final pattern = '%${_escapeLike(keyword)}%';
      where.add(
        r"(title LIKE ? ESCAPE '\' OR body LIKE ? ESCAPE '\' "
        r"OR EXISTS (SELECT 1 FROM note_tag nt2 JOIN tag t ON t.id = nt2.tag_id "
        r"WHERE nt2.note_id = notes.id AND t.name LIKE ? ESCAPE '\'))",
      );
      args.add(pattern);
      args.add(pattern);
      args.add(pattern);
    }

    final rows = _database.select('''
      SELECT * FROM notes
      WHERE ${where.join(' AND ')}
      ORDER BY ${_orderBy(sort)}
    ''', args);
    return rows.map(Note.fromRow).toList();
  }

  /// Pinned notes stay on top whatever the sort is (F-06/F-25).
  String _orderBy(NoteSort sort) {
    return switch (sort) {
      NoteSort.updated => 'pinned DESC, updated_at DESC',
      NoteSort.created => 'pinned DESC, created_at DESC',
      NoteSort.title =>
        'pinned DESC, title COLLATE NOCASE ASC, updated_at DESC',
    };
  }

  /// Last sort chosen on the list screen, defaulting to updated-at (F-25).
  NoteSort loadSortOrder() {
    final rows = _database.select(
      "SELECT value FROM setting WHERE key = 'note_sort'",
    );
    if (rows.isEmpty) return NoteSort.updated;
    return NoteSort.fromValue(rows.first['value'] as String?);
  }

  void saveSortOrder(NoteSort sort) {
    _database.execute(
      "INSERT INTO setting (key, value) VALUES ('note_sort', ?) "
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [sort.value],
    );
  }

  String _escapeLike(String input) {
    return input
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }

  /// Live note total and how many are still unanswered (F-52).
  ({int total, int todo}) noteCounts() {
    final row = _database.select('''
      SELECT count(*) AS total,
             coalesce(sum(CASE WHEN status = 'todo' THEN 1 ELSE 0 END), 0) AS todo
      FROM notes
      WHERE deleted_at IS NULL
    ''').first;
    return (total: row['total'] as int, todo: row['todo'] as int);
  }

  /// Lists tags with the number of live notes attached to each (F-22).
  List<Tag> listTags() {
    final rows = _database.select('''
      SELECT t.id AS id, t.name AS name, t.color AS color, count(n.id) AS note_count
      FROM tag t
      LEFT JOIN note_tag nt ON nt.tag_id = t.id
      LEFT JOIN notes n ON n.id = nt.note_id AND n.deleted_at IS NULL
      GROUP BY t.id, t.name, t.color
      ORDER BY note_count DESC, t.name COLLATE NOCASE
    ''');
    return rows.map(Tag.fromRow).toList();
  }

  /// Tags attached to each of the given notes, keyed by note id.
  ///
  /// One query for the whole visible list avoids per-row lookups.
  Map<String, List<Tag>> tagsOfNotes(Iterable<String> noteIds) {
    final ids = noteIds.toSet().toList();
    if (ids.isEmpty) return const {};
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = _database.select('''
      SELECT nt.note_id AS note_id, t.id AS id, t.name AS name,
             t.color AS color, 0 AS note_count
      FROM note_tag nt
      JOIN tag t ON t.id = nt.tag_id
      WHERE nt.note_id IN ($placeholders)
      ORDER BY t.name COLLATE NOCASE
    ''', ids);

    final result = <String, List<Tag>>{};
    for (final row in rows) {
      final noteId = row['note_id'] as String;
      (result[noteId] ??= []).add(Tag.fromRow(row));
    }
    return result;
  }

  List<Tag> tagsOfNote(String noteId) {
    return tagsOfNotes([noteId])[noteId] ?? const <Tag>[];
  }

  Tag? findTagByName(String name) {
    final rows = _database.select(
      'SELECT t.id AS id, t.name AS name, t.color AS color, '
      '0 AS note_count FROM tag t WHERE t.name = ? LIMIT 1',
      [name.trim()],
    );
    if (rows.isEmpty) return null;
    return Tag.fromRow(rows.first);
  }

  /// Creates a tag or returns the existing one with the same name.
  Tag createTag(String name) {
    final trimmed = name.trim();
    final existing = findTagByName(trimmed);
    if (existing != null) return existing;

    final tag = Tag(
      id: newTagId(),
      name: trimmed,
      color: tagColorForName(trimmed),
    );
    _database.execute(
      'INSERT INTO tag (id, name, color, created_at) VALUES (?, ?, ?, ?)',
      [
        tag.id,
        tag.name,
        tag.color,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
    return tag;
  }

  /// Sets the color shown for [id] across every tagged note.
  void updateTagColor(String id, int color) {
    _database.execute('UPDATE tag SET color = ? WHERE id = ?', [color, id]);
  }

  /// Renames a tag globally. Returns false when the name is empty or taken.
  bool renameTag(String id, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    final clash = _database.select(
      'SELECT id FROM tag WHERE name = ? AND id <> ? LIMIT 1',
      [trimmed, id],
    );
    if (clash.isNotEmpty) return false;
    _database.execute('UPDATE tag SET name = ? WHERE id = ?', [trimmed, id]);
    return true;
  }

  /// Deletes a tag. Notes keep their content and other tags (F-20).
  void deleteTag(String id) {
    _database.execute('DELETE FROM note_tag WHERE tag_id = ?', [id]);
    _database.execute('DELETE FROM tag WHERE id = ?', [id]);
  }

  void setNoteTags(String noteId, Iterable<String> tagIds) {
    _database.execute('BEGIN');
    try {
      _database.execute('DELETE FROM note_tag WHERE note_id = ?', [noteId]);
      for (final tagId in tagIds.toSet()) {
        _database.execute(
          'INSERT OR IGNORE INTO note_tag (note_id, tag_id) VALUES (?, ?)',
          [noteId, tagId],
        );
      }
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  Note? findById(String id) {
    final rows = _database.select('SELECT * FROM notes WHERE id = ? LIMIT 1', [
      id,
    ]);
    if (rows.isEmpty) return null;
    return Note.fromRow(rows.first);
  }

  void addAttachment({
    required String id,
    required String noteId,
    required String relativePath,
    required String mime,
    required int byteSize,
  }) {
    _database.execute(
      '''
      INSERT INTO attachment (id, note_id, relative_path, mime, byte_size, created_at)
      VALUES (?, ?, ?, ?, ?, ?)
      ''',
      [
        id,
        noteId,
        relativePath,
        mime,
        byteSize,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }

  void upsert(Note note) {
    _database.execute(
      '''
      INSERT INTO notes (id, title, body, status, pinned, favorite, created_at, updated_at, deleted_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL)
      ON CONFLICT(id) DO UPDATE SET
        title = excluded.title,
        body = excluded.body,
        status = excluded.status,
        pinned = excluded.pinned,
        favorite = excluded.favorite,
        updated_at = excluded.updated_at
      ''',
      [
        note.id,
        note.title,
        note.body,
        note.status.value,
        note.pinned ? 1 : 0,
        note.favorite ? 1 : 0,
        note.createdAt,
        note.updatedAt,
      ],
    );
    bumpBackupChangeCount();
  }

  void delete(String id) {
    _database.execute('DELETE FROM note_tag WHERE note_id = ?', [id]);
    _database.execute('DELETE FROM notes WHERE id = ?', [id]);
  }

  /// Moves a note into the recycle bin (F-04).
  void softDelete(String id) {
    _database.execute('UPDATE notes SET deleted_at = ? WHERE id = ?', [
      DateTime.now().millisecondsSinceEpoch,
      id,
    ]);
  }

  /// Returns a trashed note to the live list.
  void restore(String id) {
    _database.execute('UPDATE notes SET deleted_at = NULL WHERE id = ?', [id]);
  }

  /// Trashed notes, most recently deleted first.
  List<Note> listTrashed() {
    final rows = _database.select('''
      SELECT * FROM notes
      WHERE deleted_at IS NOT NULL
      ORDER BY deleted_at DESC
    ''');
    return rows.map(Note.fromRow).toList();
  }

  /// Permanently removes one trashed note.
  ///
  /// Returns the attachment references that the caller should delete from
  /// disk; the database layer does not own the files.
  List<String> purge(String noteId) => _purgeNotes('id = ?', [noteId]);

  List<String> purgeAll() => _purgeNotes(null, const []);

  /// Drops notes deleted more than [days] days ago (F-04).
  List<String> purgeExpired({int days = 30}) {
    final cutoff = DateTime.now()
        .subtract(Duration(days: days))
        .millisecondsSinceEpoch;
    return _purgeNotes('deleted_at IS NOT NULL AND deleted_at < ?', [cutoff]);
  }

  /// Reads a value from the settings table (F-43/F-44/F-47 and later).
  String? getSetting(String key) {
    final rows = _database.select(
      'SELECT value FROM setting WHERE key = ? LIMIT 1',
      [key],
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  void setSetting(String key, String value) {
    _database.execute(
      'INSERT INTO setting (key, value) VALUES (?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [key, value],
    );
  }

  void removeSetting(String key) {
    _database.execute('DELETE FROM setting WHERE key = ?', [key]);
  }

  /// Recent search terms, newest first, at most 20 (F-29).
  List<String> searchHistory() {
    final raw = getSetting('search_history');
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<String>()
            .where((term) => term.trim().isNotEmpty)
            .take(20)
            .toList();
      }
    } catch (_) {
      // A corrupted value must not break the search field.
    }
    return const [];
  }

  void addSearchHistory(String term) {
    final value = term.trim();
    if (value.isEmpty) return;
    // searchHistory() may return an unmodifiable const list.
    final history = List<String>.of(searchHistory())..remove(value);
    history.insert(0, value);
    if (history.length > 20) history.removeRange(20, history.length);
    setSetting('search_history', jsonEncode(history));
  }

  void removeSearchHistory(String term) {
    final history = List<String>.of(searchHistory())..remove(term);
    setSetting('search_history', jsonEncode(history));
  }

  void clearSearchHistory() => setSetting('search_history', '[]');

  /// Live notes only, used by the empty state and the statistics later.
  int countLiveNotes() {
    final rows = _database.select(
      'SELECT count(*) AS total FROM notes WHERE deleted_at IS NULL',
    );
    return rows.first['total'] as int;
  }

  /// Note writes accumulated since the last automatic backup (F-43).
  int backupChangeCount() {
    return int.tryParse(getSetting('backup_change_count') ?? '') ?? 0;
  }

  void bumpBackupChangeCount() {
    setSetting('backup_change_count', '${backupChangeCount() + 1}');
  }

  void resetBackupChangeCount() => setSetting('backup_change_count', '0');

  /// Every note including the recycle bin, oldest first (F-38).
  List<Note> allNotesForBackup() {
    final rows = _database.select(
      'SELECT * FROM notes ORDER BY created_at ASC',
    );
    return rows.map(Note.fromRow).toList();
  }

  List<Map<String, Object?>> allTagsForBackup() =>
      _rowsOf(_database.select('SELECT * FROM tag ORDER BY created_at ASC'));

  List<Map<String, Object?>> allNoteTagsForBackup() =>
      _rowsOf(_database.select('SELECT * FROM note_tag'));

  List<Map<String, Object?>> allAttachmentsForBackup() => _rowsOf(
    _database.select('SELECT * FROM attachment ORDER BY created_at ASC'),
  );

  /// Attachment rows for the given notes, used when exporting a ZIP (F-37).
  List<Map<String, Object?>> attachmentsOfNotes(Iterable<String> noteIds) {
    final ids = noteIds.toSet().toList();
    if (ids.isEmpty) return const [];
    final placeholders = List.filled(ids.length, '?').join(',');
    return _rowsOf(
      _database.select(
        'SELECT * FROM attachment WHERE note_id IN ($placeholders)',
        ids,
      ),
    );
  }

  /// Notes in [payload] whose id already exists locally (F-39).
  int countDuplicateNotes(Map<String, Object?> payload) {
    int duplicate = 0;
    for (final row in _mapList(payload['notes'])) {
      final id = row['id'];
      if (id is! String || id.isEmpty) continue;
      final existing = _database.select(
        'SELECT 1 FROM notes WHERE id = ? LIMIT 1',
        [id],
      );
      if (existing.isNotEmpty) duplicate++;
    }
    return duplicate;
  }

  /// Applies a decoded JSON backup (F-39/F-44).
  ///
  /// With [replaceAll] the current database is wiped first, which is the
  /// restore path of F-44. Otherwise notes are merged in: duplicates are
  /// overwritten or skipped according to [overwriteDuplicates].
  BackupImportResult importBackup(
    Map<String, Object?> payload, {
    bool overwriteDuplicates = true,
    bool replaceAll = false,
  }) {
    final notes = _mapList(payload['notes']);
    final tags = _mapList(payload['tags']);
    final noteTags = _mapList(payload['note_tags']);
    final attachments = _mapList(payload['attachments']);
    final now = DateTime.now().millisecondsSinceEpoch;

    int imported = 0;
    int skipped = 0;
    int duplicates = 0;
    final tagIdMap = <String, String>{};
    final skippedNoteIds = <String>{};

    _database.execute('BEGIN');
    try {
      if (replaceAll) {
        _database.execute('DELETE FROM note_tag');
        _database.execute('DELETE FROM attachment');
        _database.execute('DELETE FROM notes');
        _database.execute('DELETE FROM tag');
      }

      for (final row in tags) {
        final id = row['id'];
        final name = (row['name'] as String? ?? '').trim();
        if (id is! String || id.isEmpty || name.isEmpty) continue;
        if (!replaceAll) {
          // An existing tag keeps its id, whether matched by id or by name.
          if (_database.select('SELECT id FROM tag WHERE id = ? LIMIT 1', [
            id,
          ]).isNotEmpty) {
            tagIdMap[id] = id;
            continue;
          }
          final byName = _database.select(
            'SELECT id FROM tag WHERE name = ? LIMIT 1',
            [name],
          );
          if (byName.isNotEmpty) {
            tagIdMap[id] = byName.first['id'] as String;
            continue;
          }
        }
        _database.execute(
          'INSERT INTO tag (id, name, color, created_at) VALUES (?, ?, ?, ?) '
          'ON CONFLICT(id) DO UPDATE SET name = excluded.name',
          [
            id,
            name,
            (row['color'] as int?) ?? tagColorForName(name),
            _millisOf(row['created_at'], now),
          ],
        );
        tagIdMap[id] = id;
      }

      for (final row in notes) {
        final id = row['id'];
        if (id is! String || id.isEmpty) {
          skipped++;
          continue;
        }
        final exists = _database.select(
          'SELECT 1 FROM notes WHERE id = ? LIMIT 1',
          [id],
        ).isNotEmpty;
        if (exists) {
          duplicates++;
          if (!overwriteDuplicates) {
            skipped++;
            skippedNoteIds.add(id);
            continue;
          }
          _database.execute(
            '''
            UPDATE notes SET title = ?, body = ?, status = ?, pinned = ?,
              favorite = ?, created_at = ?, updated_at = ?, deleted_at = ?
            WHERE id = ?
            ''',
            [
              row['title'] as String? ?? '',
              row['body'] as String? ?? '',
              row['status'] == 'done' ? 'done' : 'todo',
              row['pinned'] == 1 || row['pinned'] == true ? 1 : 0,
              row['favorite'] == 1 || row['favorite'] == true ? 1 : 0,
              _millisOf(row['created_at'], now),
              _millisOf(row['updated_at'], now),
              _nullableMillis(row['deleted_at']),
              id,
            ],
          );
          // The backup row wins for associations as well.
          _database.execute('DELETE FROM note_tag WHERE note_id = ?', [id]);
          _database.execute('DELETE FROM attachment WHERE note_id = ?', [id]);
        } else {
          _database.execute(
            '''
            INSERT INTO notes (id, title, body, status, pinned, favorite,
              created_at, updated_at, deleted_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''',
            [
              id,
              row['title'] as String? ?? '',
              row['body'] as String? ?? '',
              row['status'] == 'done' ? 'done' : 'todo',
              row['pinned'] == 1 || row['pinned'] == true ? 1 : 0,
              row['favorite'] == 1 || row['favorite'] == true ? 1 : 0,
              _millisOf(row['created_at'], now),
              _millisOf(row['updated_at'], now),
              _nullableMillis(row['deleted_at']),
            ],
          );
        }
        imported++;
      }

      for (final row in noteTags) {
        final noteId = row['note_id'];
        final tagId = row['tag_id'];
        if (noteId is! String || tagId is! String) continue;
        if (skippedNoteIds.contains(noteId)) continue;
        final mapped = tagIdMap[tagId];
        if (mapped == null) continue;
        _database.execute(
          'INSERT OR IGNORE INTO note_tag (note_id, tag_id) VALUES (?, ?)',
          [noteId, mapped],
        );
      }

      for (final row in attachments) {
        final noteId = row['note_id'];
        final id = row['id'];
        final path = row['relative_path'];
        if (noteId is! String || id is! String || path is! String) continue;
        if (skippedNoteIds.contains(noteId)) continue;
        _database.execute(
          '''
          INSERT INTO attachment (id, note_id, relative_path, mime, width,
            height, byte_size, created_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            note_id = excluded.note_id,
            relative_path = excluded.relative_path,
            mime = excluded.mime,
            width = excluded.width,
            height = excluded.height,
            byte_size = excluded.byte_size
          ''',
          [
            id,
            noteId,
            path,
            row['mime'] as String? ?? 'image/jpeg',
            row['width'] as int?,
            row['height'] as int?,
            row['byte_size'] as int?,
            _millisOf(row['created_at'], now),
          ],
        );
      }

      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
    return BackupImportResult(
      imported: imported,
      skipped: skipped,
      duplicates: duplicates,
    );
  }

  static List<Map<String, Object?>> _rowsOf(
    Iterable<Map<String, Object?>> rows,
  ) {
    return rows.map((row) => Map<String, Object?>.from(row)).toList();
  }

  static List<Map<String, Object?>> _mapList(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, Object?>.from(row))
        .toList();
  }

  static int _millisOf(Object? value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return fallback;
  }

  static int? _nullableMillis(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  List<String> _purgeNotes(String? condition, List<Object?> args) {
    final ids = _database
        .select(
          'SELECT id FROM notes ${condition == null ? '' : 'WHERE $condition'}',
          args,
        )
        .map((row) => row['id'] as String)
        .toList();
    if (ids.isEmpty) return const [];

    final placeholders = List.filled(ids.length, '?').join(',');
    final paths = _database
        .select(
          'SELECT relative_path FROM attachment WHERE note_id IN ($placeholders)',
          ids,
        )
        .map((row) => row['relative_path'] as String)
        .toList();

    _database.execute('BEGIN');
    try {
      _database.execute(
        'DELETE FROM note_tag WHERE note_id IN ($placeholders)',
        ids,
      );
      _database.execute(
        'DELETE FROM attachment WHERE note_id IN ($placeholders)',
        ids,
      );
      _database.execute('DELETE FROM notes WHERE id IN ($placeholders)', ids);
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
    return paths;
  }
}

/// Outcome of a JSON backup import (F-39).
class BackupImportResult {
  const BackupImportResult({
    required this.imported,
    required this.skipped,
    required this.duplicates,
  });

  final int imported;
  final int skipped;

  /// Notes that already existed locally.
  final int duplicates;
}

/// Generates a sortable, collision-resistant local id.
String newNoteId() {
  return _newLocalId();
}

String newTagId() {
  return _newLocalId();
}

String newAttachmentId() {
  return _newLocalId();
}

String _newLocalId() {
  final rand = Random();
  final suffix = rand.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
  return '${DateTime.now().microsecondsSinceEpoch}-$suffix';
}
