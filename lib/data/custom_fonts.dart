import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'notes_db.dart';

/// Flutter family name used for an imported font id.
///
/// Flutter can only resolve a dynamic font through `FontLoader`, and the
/// family string is the only handle on it, so the id has to be encoded here.
String fontFamilyFor(String id) => 'JiwenFont_$id';

/// A font file the user imported from the device.
///
/// Only `.ttf` / `.otf` are accepted: they are single files, load through
/// `FontLoader` at runtime and need no rebuild of the app.
class ImportedFont {
  const ImportedFont({
    required this.id,
    required this.name,
    required this.fileName,
  });

  final String id;

  /// Display name, defaulting to the file name without its extension.
  final String name;

  /// File name inside the private font directory.
  final String fileName;

  String get family => fontFamilyFor(id);

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'file': fileName};

  static ImportedFont? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    final file = json['file'];
    if (id is! String || name is! String || file is! String) return null;
    if (id.isEmpty || file.isEmpty) return null;
    return ImportedFont(id: id, name: name, fileName: file);
  }
}

/// Raised when a picked file cannot be used as an app font.
class FontImportException implements Exception {
  const FontImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Owns the imported fonts: copies them into private storage, registers them
/// with the engine and remembers which ones the user keeps.
class CustomFonts {
  CustomFonts._();

  static final CustomFonts instance = CustomFonts._();

  static const _storageKey = 'pref_custom_fonts';
  static const _folder = 'fonts';

  /// Extensions shown in the file picker and accepted by [add].
  static const supportedExtensions = ['ttf', 'otf'];

  /// Guard against handing a whole system font collection to the engine.
  static const maxBytes = 24 * 1024 * 1024;

  Directory? _dir;
  List<ImportedFont> _fonts = const [];
  final Set<String> _loaded = {};

  List<ImportedFont> get fonts => List.unmodifiable(_fonts);

  ImportedFont? byId(String? id) {
    if (id == null) return null;
    for (final font in _fonts) {
      if (font.id == id) return font;
    }
    return null;
  }

  /// Reads the stored list and registers every font that still exists.
  ///
  /// Runs before `runApp` so the first frame can already use the font family
  /// the user picked last time.
  Future<void> init() async {
    if (_dir != null) return;
    final support = await getApplicationSupportDirectory();
    _dir = Directory(p.join(support.path, _folder));
    await _dir!.create(recursive: true);

    _fonts = _readStored();
    final alive = <ImportedFont>[];
    for (final font in _fonts) {
      final file = File(p.join(_dir!.path, font.fileName));
      if (!file.existsSync()) continue;
      try {
        await _register(font);
        alive.add(font);
      } catch (_) {
        // A damaged file must never stop the app from starting.
      }
    }
    if (alive.length != _fonts.length) {
      _fonts = alive;
      _store();
    }
  }

  /// Copies [sourcePath] into private storage and registers it.
  ///
  /// Throws [FontImportException] with a user-facing message.
  Future<ImportedFont> add({
    required String sourcePath,
    required String displayName,
  }) async {
    await init();
    final extension = p.extension(sourcePath).toLowerCase();
    final bare = extension.replaceFirst('.', '');
    if (!supportedExtensions.contains(bare)) {
      throw const FontImportException('只支持 .ttf 或 .otf 字体文件');
    }
    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw const FontImportException('无法读取该文件');
    }
    if (source.lengthSync() > maxBytes) {
      throw const FontImportException('字体文件太大，上限 24 MB');
    }

    final id = _newId();
    final font = ImportedFont(
      id: id,
      name: displayName.trim().isEmpty ? '自定义字体' : displayName.trim(),
      fileName: '$id$extension',
    );
    final target = File(p.join(_dir!.path, font.fileName));
    await source.copy(target.path);
    try {
      await _register(font);
    } catch (_) {
      try {
        await target.delete();
      } on FileSystemException {
        // Nothing else to clean up.
      }
      throw const FontImportException('这个文件不是可用的字体');
    }

    _fonts = [..._fonts, font];
    _store();
    return font;
  }

  /// Forgets a font and deletes its file. The engine keeps the glyphs in
  /// memory until the next launch, which is harmless.
  Future<void> remove(ImportedFont font) async {
    _fonts = _fonts.where((item) => item.id != font.id).toList(growable: false);
    _loaded.remove(font.family);
    _store();
    final dir = _dir;
    if (dir == null) return;
    try {
      final file = File(p.join(dir.path, font.fileName));
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // A locked file is left behind; the entry is already gone.
    }
  }

  Future<void> _register(ImportedFont font) async {
    if (_loaded.contains(font.family)) return;
    final file = File(p.join(_dir!.path, font.fileName));
    final bytes = await file.readAsBytes();
    final loader = FontLoader(font.family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    _loaded.add(font.family);
  }

  List<ImportedFont> _readStored() {
    final raw = NotesDb.instance.getSetting(_storageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map(ImportedFont.fromJson)
          .whereType<ImportedFont>()
          .toList(growable: false);
    } on FormatException {
      return const [];
    }
  }

  void _store() {
    NotesDb.instance.setSetting(
      _storageKey,
      jsonEncode([for (final font in _fonts) font.toJson()]),
    );
  }

  String _newId() {
    final suffix = Random().nextInt(0xFFFF).toRadixString(16).padLeft(4, '0');
    return '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}$suffix';
  }
}
