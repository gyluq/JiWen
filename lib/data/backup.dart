import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/note.dart';
import 'attachments.dart';
import 'notes_db.dart';

/// One entry of the local backup list (F-44).
class BackupEntry {
  const BackupEntry({
    required this.file,
    required this.modified,
    required this.size,
  });

  final File file;
  final DateTime modified;
  final int size;

  /// ZIP backups embed the images, legacy JSON backups only carry paths.
  bool get hasImages => file.path.toLowerCase().endsWith('.zip');
}

/// A decoded backup: the database document plus any embedded image bytes.
class BackupBundle {
  const BackupBundle({required this.payload, this.files = const {}});

  final Map<String, Object?> payload;

  /// Archive paths (`attachments/<name>`) mapped to their bytes.
  final Map<String, List<int>> files;
}

/// Builds and restores the backups used by F-38 / F-39 / F-43 / F-44.
///
/// Local backups are ZIP archives holding `backup.json` plus every attachment
/// file, so restoring after images were purged brings the pictures back.
/// The exported F-38 JSON keeps just the paths; it is meant for sharing and
/// re-importing on the same installation.
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const _backupJsonVersion = 1;
  static const _keepCount = 5;
  static const _lastDateKey = 'backup_last_date';

  Directory? _dir;

  Future<Directory> _backupDir() async {
    final existing = _dir;
    if (existing != null) return existing;
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'backups'));
    await dir.create(recursive: true);
    return _dir = dir;
  }

  /// Serializes the whole database into the backup document (F-38).
  Map<String, Object?> buildPayload() {
    final db = NotesDb.instance;
    return {
      'app': 'jiwen',
      'version': _backupJsonVersion,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'notes': db.allNotesForBackup().map(_noteToJson).toList(),
      'tags': db.allTagsForBackup(),
      'note_tags': db.allNoteTagsForBackup(),
      'attachments': db.allAttachmentsForBackup(),
    };
  }

  Map<String, Object?> _noteToJson(Note note) {
    return {
      'id': note.id,
      'title': note.title,
      'body': note.body,
      'status': note.status.value,
      'pinned': note.pinned,
      'favorite': note.favorite,
      'created_at': note.createdAt,
      'updated_at': note.updatedAt,
      'deleted_at': note.deletedAt,
    };
  }

  /// Latest backups, newest first (F-44).
  Future<List<BackupEntry>> listBackups() async {
    final dir = await _backupDir();
    if (!dir.existsSync()) return const [];
    final entries = <BackupEntry>[];
    for (final entity in dir.listSync()) {
      if (entity is! File || !_isBackupName(p.basename(entity.path))) continue;
      final stat = entity.statSync();
      entries.add(
        BackupEntry(file: entity, modified: stat.modified, size: stat.size),
      );
    }
    entries.sort((a, b) => b.modified.compareTo(a.modified));
    return entries;
  }

  /// Creates a self-contained backup and keeps the newest [_keepCount] files
  /// (F-43).
  Future<File> createBackup() async {
    final dir = await _backupDir();
    final archive = await _buildArchive();
    final file = _newFile(dir, 'jiwen_backup', '.zip');
    await file.writeAsBytes(ZipEncoder().encodeBytes(archive));
    await _prune(dir);
    return file;
  }

  /// Writes a path-only JSON copy into the cache so it can be shared (F-38).
  Future<File> exportJsonFile() async {
    final cache = await getTemporaryDirectory();
    final dir = Directory(p.join(cache.path, 'exports'));
    await dir.create(recursive: true);
    final file = _newFile(dir, 'jiwen_backup', '.json');
    await file.writeAsString(jsonEncode(buildPayload()));
    return file;
  }

  /// ZIP backup: `backup.json` plus one file per attachment (F-44).
  Future<Archive> _buildArchive() async {
    final archive = Archive();
    final jsonBytes = utf8.encode(jsonEncode(buildPayload()));
    archive.addFile(ArchiveFile('backup.json', jsonBytes.length, jsonBytes));

    for (final row in NotesDb.instance.allAttachmentsForBackup()) {
      final relative = row['relative_path'];
      if (relative is! String) continue;
      final name = _attachmentName(relative);
      if (name == null) continue;
      final file = AttachmentStore.instance.resolve(relative);
      if (file == null || !file.existsSync()) continue;
      try {
        final bytes = await file.readAsBytes();
        archive.addFile(ArchiveFile('attachments/$name', bytes.length, bytes));
      } on FileSystemException {
        // A single unreadable image must not abort the backup.
      }
    }
    return archive;
  }

  File _newFile(Directory dir, String prefix, String extension) {
    final base = '${prefix}_${_fileStamp(DateTime.now())}';
    var candidate = File(p.join(dir.path, '$base$extension'));
    var index = 2;
    while (candidate.existsSync()) {
      candidate = File(p.join(dir.path, '${base}_$index$extension'));
      index++;
    }
    return candidate;
  }

  Future<void> _prune(Directory dir) async {
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((file) => _isBackupName(p.basename(file.path)))
            .toList()
          ..sort(
            (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
          );
    for (final old in files.skip(_keepCount)) {
      try {
        old.deleteSync();
      } on FileSystemException {
        // A file that cannot be removed is simply kept.
      }
    }
  }

  bool _isBackupName(String name) {
    if (!name.startsWith('jiwen_backup_')) return false;
    return name.endsWith('.zip') || name.endsWith('.json');
  }

  /// Reads a backup from disk, whether it is a ZIP or a legacy JSON file.
  Future<BackupBundle> readBundle(File file) async {
    return decodeBundle(file.path, await file.readAsBytes());
  }

  BackupBundle decodeBundle(String fileName, List<int> bytes) {
    if (fileName.toLowerCase().endsWith('.zip')) {
      final archive = ZipDecoder().decodeBytes(bytes);
      ArchiveFile? document;
      final files = <String, List<int>>{};
      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        if (entry.name == 'backup.json') {
          document = entry;
        } else if (entry.name.startsWith('attachments/')) {
          files[entry.name] = entry.content;
        }
      }
      if (document == null) {
        throw const FormatException('备份包缺少 backup.json');
      }
      return BackupBundle(
        payload: decodePayload(
          utf8.decode(document.content, allowMalformed: true),
        ),
        files: files,
      );
    }
    return BackupBundle(
      payload: decodePayload(utf8.decode(bytes, allowMalformed: true)),
    );
  }

  Map<String, Object?> decodePayload(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const FormatException('备份文件格式不正确');
    }
    final payload = Map<String, Object?>.from(decoded);
    if (payload['notes'] is! List) {
      throw const FormatException('备份文件缺少笔记数据');
    }
    return payload;
  }

  /// Merges a backup into the current data (F-39).
  Future<BackupImportResult> importBundle(
    BackupBundle bundle, {
    required bool overwriteDuplicates,
  }) async {
    final result = NotesDb.instance.importBackup(
      bundle.payload,
      overwriteDuplicates: overwriteDuplicates,
    );
    await _writeAttachments(bundle.files);
    return result;
  }

  /// Replaces all local data with the backup content (F-44).
  Future<BackupImportResult> restoreBundle(BackupBundle bundle) async {
    final result = NotesDb.instance.importBackup(
      bundle.payload,
      replaceAll: true,
    );
    await _writeAttachments(bundle.files);
    return result;
  }

  /// Puts embedded images back into the private attachment directory.
  Future<void> _writeAttachments(Map<String, List<int>> files) async {
    if (files.isEmpty) return;
    final dir = await AttachmentStore.instance.attachmentsDir();
    for (final entry in files.entries) {
      final name = _attachmentName(entry.key);
      if (name == null) continue;
      try {
        await File(p.join(dir.path, name))
            .writeAsBytes(entry.value, flush: false);
      } on FileSystemException {
        // One failed image must not abort the restore.
      }
    }
  }

  /// Flat attachment names only, which also blocks path traversal.
  static String? _attachmentName(String relative) {
    final normalized = relative.replaceAll('\\', '/');
    const prefix = 'attachments/';
    if (!normalized.startsWith(prefix)) return null;
    final name = normalized.substring(prefix.length);
    if (name.isEmpty || name.contains('/') || name == '.' || name == '..') {
      return null;
    }
    return name;
  }

  /// Runs at launch and after note writes (F-43).
  ///
  /// A backup is made on the first launch of a day, or once 50 note writes
  /// accumulated since the last one. Returns true when it created a file.
  Future<bool> maybeAutoBackup() async {
    final db = NotesDb.instance;
    final today = _dayStamp(DateTime.now());
    final lastDate = db.getSetting(_lastDateKey);
    final changes = db.backupChangeCount();
    final firstToday = lastDate != today;
    if (!firstToday && changes < 50) return false;
    if (db.countLiveNotes() == 0 && changes < 50) {
      // Nothing worth archiving yet; keep waiting for the first note.
      return false;
    }

    await createBackup();
    db.setSetting(_lastDateKey, today);
    db.resetBackupChangeCount();
    return true;
  }

  static String _dayStamp(DateTime time) {
    return '${time.year.toString().padLeft(4, '0')}'
        '${time.month.toString().padLeft(2, '0')}'
        '${time.day.toString().padLeft(2, '0')}';
  }

  static String _fileStamp(DateTime time) {
    return '${_dayStamp(time)}_'
        '${time.hour.toString().padLeft(2, '0')}'
        '${time.minute.toString().padLeft(2, '0')}'
        '${time.second.toString().padLeft(2, '0')}';
  }
}
