import 'package:flutter/material.dart';

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
  static const _keyHomeView = 'pref_home_view';
  static const _keyOpenNew = 'pref_open_new_note';
  static const _keyListDensity = 'pref_list_density';

  AppThemeChoice themeMode = AppThemeChoice.system;
  AppFontSize fontSize = AppFontSize.normal;
  AppHomeView homeView = AppHomeView.all;
  bool openToNewNote = false;
  AppListDensity listDensity = AppListDensity.compact;

  double get bodyScale => fontSize.scale;

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
