import 'package:flutter/material.dart';

import 'custom_fonts.dart';
import 'notes_db.dart';

/// Appearance modes offered by F-46.
enum AppThemeChoice {
  system('跟随系统'),
  light('浅色'),
  dark('深色');

  const AppThemeChoice(this.label);

  final String label;

  ThemeMode get materialMode => switch (this) {
    AppThemeChoice.system => ThemeMode.system,
    AppThemeChoice.light => ThemeMode.light,
    AppThemeChoice.dark => ThemeMode.dark,
  };
}

/// Body text sizes offered by F-47 (four levels, within the required 3-5).
enum AppFontSize {
  small('小', 0.9),
  normal('标准', 1.0),
  large('大', 1.12),
  huge('特大', 1.24);

  const AppFontSize(this.label, this.scale);

  final String label;
  final double scale;
}

/// Font families offered by the appearance settings.
///
/// The serif family is bundled so Chinese text renders the same on every
/// device, at the cost of a larger APK.
enum AppFontFamily {
  system('系统默认', null),
  serif('宋体', 'NotoSerifSC');

  const AppFontFamily(this.label, this.family);

  final String label;
  final String? family;
}

/// Default list view at launch (F-48).
enum AppHomeView {
  all('全部笔记'),
  todo('待解答'),
  favorites('收藏');

  const AppHomeView(this.label);

  final String label;
}

/// List density offered by F-31; the excerpt line count follows F-32.
enum AppListDensity {
  compact('紧凑', 1, 10),
  standard('标准', 2, 12),
  loose('宽松', 3, 16);

  const AppListDensity(this.label, this.excerptLines, this.verticalPadding);

  final String label;
  final int excerptLines;
  final double verticalPadding;
}

/// App-wide preferences persisted in the `setting` table.
///
/// A single lightweight ChangeNotifier is enough here; the root widget listens
/// to it so a theme change repaints the app.
class AppSettings extends ChangeNotifier {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  static const _keyTheme = 'pref_theme_mode';
  static const _keyFontSize = 'pref_font_size';
  static const _keyFontFamily = 'pref_font_family';
  static const _keyImportedFont = 'pref_imported_font';
  static const _keyHomeView = 'pref_home_view';
  static const _keyOpenNew = 'pref_open_new_note';
  static const _keyListDensity = 'pref_list_density';

  AppThemeChoice themeMode = AppThemeChoice.system;
  AppFontSize fontSize = AppFontSize.normal;
  AppFontFamily fontFamily = AppFontFamily.system;

  /// Id of the imported font in use, or null when a built-in family is active.
  String? importedFontId;

  AppHomeView homeView = AppHomeView.all;
  bool openToNewNote = false;
  AppListDensity listDensity = AppListDensity.compact;

  double get bodyScale => fontSize.scale;

  /// Family handed to the theme; imported fonts win over the built-in ones.
  String? get fontFamilyName {
    final id = importedFontId;
    return id == null ? fontFamily.family : fontFamilyFor(id);
  }

  /// Reads persisted values after NotesDb.init().
  void load() {
    final db = NotesDb.instance;
    themeMode = _enumBy(
      AppThemeChoice.values,
      db.getSetting(_keyTheme),
      AppThemeChoice.system,
      (value) => value.name,
    );
    fontSize = _enumBy(
      AppFontSize.values,
      db.getSetting(_keyFontSize),
      AppFontSize.normal,
      (value) => value.name,
    );
    fontFamily = _enumBy(
      AppFontFamily.values,
      db.getSetting(_keyFontFamily),
      AppFontFamily.system,
      (value) => value.name,
    );
    final imported = db.getSetting(_keyImportedFont);
    importedFontId = imported == null || imported.isEmpty ? null : imported;
    homeView = _enumBy(
      AppHomeView.values,
      db.getSetting(_keyHomeView),
      AppHomeView.all,
      (value) => value.name,
    );
    openToNewNote = db.getSetting(_keyOpenNew) == '1';
    listDensity = _enumBy(
      AppListDensity.values,
      db.getSetting(_keyListDensity),
      AppListDensity.compact,
      (value) => value.name,
    );
  }

  void setThemeMode(AppThemeChoice value) {
    if (themeMode == value) return;
    themeMode = value;
    NotesDb.instance.setSetting(_keyTheme, value.name);
    notifyListeners();
  }

  void setFontSize(AppFontSize value) {
    if (fontSize == value) return;
    fontSize = value;
    NotesDb.instance.setSetting(_keyFontSize, value.name);
    notifyListeners();
  }

  void setFontFamily(AppFontFamily value) {
    final cleared = importedFontId != null;
    if (fontFamily == value && !cleared) return;
    fontFamily = value;
    importedFontId = null;
    NotesDb.instance.setSetting(_keyFontFamily, value.name);
    if (cleared) NotesDb.instance.setSetting(_keyImportedFont, '');
    notifyListeners();
  }

  /// Switches to an imported font, or back to the built-in families when
  /// [id] is null.
  void setImportedFont(String? id) {
    if (importedFontId == id) return;
    importedFontId = id;
    NotesDb.instance.setSetting(_keyImportedFont, id ?? '');
    notifyListeners();
  }

  /// Drops an imported font that is no longer on disk (removed file or a
  /// restored settings row), so the app never asks for a missing family.
  void syncImportedFont(Iterable<String> availableIds) {
    final id = importedFontId;
    if (id == null) return;
    if (availableIds.contains(id)) return;
    importedFontId = null;
    NotesDb.instance.setSetting(_keyImportedFont, '');
  }

  void setHomeView(AppHomeView value) {
    if (homeView == value) return;
    homeView = value;
    NotesDb.instance.setSetting(_keyHomeView, value.name);
    notifyListeners();
  }

  void setOpenToNewNote(bool value) {
    if (openToNewNote == value) return;
    openToNewNote = value;
    NotesDb.instance.setSetting(_keyOpenNew, value ? '1' : '0');
    notifyListeners();
  }

  void setListDensity(AppListDensity value) {
    if (listDensity == value) return;
    listDensity = value;
    NotesDb.instance.setSetting(_keyListDensity, value.name);
    notifyListeners();
  }

  static T _enumBy<T>(
    List<T> values,
    String? stored,
    T fallback,
    String Function(T value) nameOf,
  ) {
    for (final value in values) {
      if (nameOf(value) == stored) return value;
    }
    return fallback;
  }
}
