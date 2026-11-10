import 'package:flutter/material.dart';

import 'data/app_lock.dart';
import 'data/app_settings.dart';
import 'data/attachments.dart';
import 'data/backup.dart';
import 'data/custom_fonts.dart';
import 'data/notes_db.dart';
import 'screens/lock_screen.dart';
import 'screens/note_list_screen.dart';
import 'theme.dart';
import 'util/secure_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotesDb.instance.init();
  await AttachmentStore.instance.init();
  AppSettings.instance.load();
  // Imported fonts have to be registered before the first frame, otherwise the
  // chosen family would fall back to the system font.
  try {
    await CustomFonts.instance.init();
  } catch (_) {
    // A broken font directory must not block the app.
  }
  AppSettings.instance.syncImportedFont(
    CustomFonts.instance.fonts.map((font) => font.id),
  );
  // Notes kept in the recycle bin for more than 30 days are dropped on start.
  AttachmentStore.instance.deleteReferences(NotesDb.instance.purgeExpired());
  // F-43: the first launch of a day (or 50 accumulated writes) makes a backup.
  try {
    await BackupService.instance.maybeAutoBackup();
  } catch (_) {
    // A failed backup must never block the app from starting.
  }
  runApp(const JiWenApp());
}

class JiWenApp extends StatefulWidget {
  const JiWenApp({super.key});

  @override
  State<JiWenApp> createState() => _JiWenAppState();
}

class _JiWenAppState extends State<JiWenApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  DateTime? _pausedAt;
  bool _lockVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SecureScreen.apply();
      // A cold start always asks for the PIN when the lock is enabled.
      if (AppLock.instance.enabled) _showLock();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // While the lock gate is on top the app is already protected, and the
        // pause caused by that screen's own biometric prompt must not queue
        // another lock (otherwise unlocking loops forever).
        if (!_lockVisible && AppLock.instance.enabled) {
          _pausedAt = DateTime.now();
        }
        break;
      case AppLifecycleState.resumed:
        final pausedAt = _pausedAt;
        _pausedAt = null;
        if (_lockVisible || !AppLock.instance.enabled) return;
        // No real background transition was recorded, so a resume alone (for
        // example the system dismissing a dialog) must not lock the app.
        if (pausedAt == null) return;
        if (AppLock.instance.timeout.shouldLockAfter(pausedAt)) _showLock();
        break;
      default:
        break;
    }
  }

  void _showLock() {
    if (_lockVisible) return;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showLock();
      });
      return;
    }
    _lockVisible = true;
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => LockScreen(
          onUnlocked: () {
            _lockVisible = false;
            navigator.pop();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: _navigatorKey,
          title: '记问',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(
            AppPalette.light,
            fontFamily: AppSettings.instance.fontFamilyName,
          ),
          darkTheme: buildAppTheme(
            AppPalette.dark,
            fontFamily: AppSettings.instance.fontFamilyName,
          ),
          themeMode: AppSettings.instance.themeMode.materialMode,
          builder: (context, child) {
            // Keep the hand-tuned tokens in sync with the resolved theme (F-46).
            final brightness = Theme.of(context).brightness;
            AppColors.apply(
              brightness == Brightness.dark
                  ? AppPalette.dark
                  : AppPalette.light,
            );
            return child ?? const SizedBox.shrink();
          },
          home: const NoteListScreen(),
        );
      },
    );
  }
}
