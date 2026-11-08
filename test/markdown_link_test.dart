// url_launcher_platform_interface and plugin_platform_interface are pulled in
// transitively by url_launcher; test-only fakes import them directly.
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiwen/widgets/markdown_view.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _FakeLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final List<String> launched = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

void main() {
  testWidgets('tapping a Markdown link opens it externally', (tester) async {
    final launcher = _FakeLauncher();
    UrlLauncherPlatform.instance = launcher;

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownView(source: '[示例](https://example.com/a)'),
        ),
      ),
    );

    await tester.tap(find.byType(RichText));
    await tester.pump();

    expect(launcher.launched, ['https://example.com/a']);
  });
}
