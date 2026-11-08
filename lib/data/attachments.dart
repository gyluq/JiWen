import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'notes_db.dart';

/// Owns the private image directory used by note attachments (F-14 / F-42).
class AttachmentStore {
  AttachmentStore._();
  static final AttachmentStore instance = AttachmentStore._();

  String? _baseDir;

  Future<void> init() async {
    if (_baseDir != null) return;
    _baseDir = (await getApplicationSupportDirectory()).path;
  }

  /// Resolves a Markdown reference such as `attachments/x.jpg` to a file.
  /// Remote urls and unresolved paths return null.
  File? resolve(String reference) {
    final base = _baseDir;
    if (base == null || reference.contains('://')) return null;
    return File(p.join(base, reference));
  }

  /// Directory holding every attachment file (F-14 / F-45).
  Future<Directory> attachmentsDir() async {
    await init();
    final dir = Directory(p.join(_baseDir!, 'attachments'));
    await dir.create(recursive: true);
    return dir;
  }

  /// Copies a picked image into private storage.
  ///
  /// The picker already caps both sides at 1600px and re-encodes, which also
  /// bakes in the EXIF orientation, so the stored file is ready to display.
  Future<File> save(XFile picked, {required String noteId}) async {
    await init();
    final dir = Directory(p.join(_baseDir!, 'attachments'));
    await dir.create(recursive: true);
    final extension = p.extension(picked.path).toLowerCase();
    final name =
        '${noteId}_${newNoteId()}'
        '${extension.isEmpty ? '.jpg' : extension}';
    final file = File(p.join(dir.path, name));
    await picked.saveTo(file.path);
    return file;
  }

  /// Path relative to the support directory, as written into Markdown.
  String relativePath(File file) {
    final base = _baseDir;
    if (base == null) return file.path;
    return p.relative(file.path, from: base).replaceAll(r'\', '/');
  }

  String mimeOf(File file) {
    return switch (p.extension(file.path).toLowerCase()) {
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      '.gif' => 'image/gif',
      _ => 'image/jpeg',
    };
  }

  /// Removes attachment files permanently, used when a note is purged.
  void deleteReferences(Iterable<String> references) {
    for (final reference in references) {
      final file = resolve(reference);
      if (file == null) continue;
      try {
        if (file.existsSync()) file.deleteSync();
      } on FileSystemException {
        // A missing or locked file must not block the note removal.
      }
    }
  }
}
