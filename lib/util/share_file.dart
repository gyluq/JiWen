import 'dart:io';

import 'package:share_plus/share_plus.dart';

/// Hands a generated file to the system share sheet so the user can save it
/// to Files, send it elsewhere or open it with another app.
Future<void> shareFile(File file, {String? subject}) async {
  await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path)], subject: subject ?? '记问导出'),
  );
}

/// Shares a note as Markdown text (F-35).
Future<void> shareText(String text, {String? subject}) async {
  await SharePlus.instance.share(
    ShareParams(text: text, subject: subject ?? '记问笔记'),
  );
}
