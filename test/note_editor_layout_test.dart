import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiwen/screens/note_editor_screen.dart';
import 'package:jiwen/widgets/markdown_view.dart';

/// The editor toolbar is a fixed 8×2 grid: sixteen tools, two rows of eight.
/// The edit/preview switch lives in the app bar and the word count moved to
/// the end of the document, so the layout has to survive narrow phones.
void main() {
  const tools = [
    '撤销',
    '重做',
    '标题',
    '加粗',
    '斜体',
    '删除线',
    '行内代码',
    '列表',
    '任务列表',
    '缩进',
    '取消缩进',
    '代码块',
    '表格',
    '分隔线',
    '插入图片',
    '插入链接',
  ];

  Future<void> pumpEditor(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: NoteEditorScreen()));
    await tester.pump();
  }

  for (final size in const [Size(390, 844), Size(360, 800)]) {
    testWidgets('toolbar grid fits at ${size.width.toInt()}px', (tester) async {
      await pumpEditor(tester, size);
      expect(tester.takeException(), isNull);
      expect(find.byTooltip(tools.first), findsOneWidget);
      expect(find.byTooltip(tools.last), findsOneWidget);
      for (final tool in tools) {
        expect(find.byTooltip(tool), findsOneWidget, reason: tool);
      }
    });
  }

  testWidgets('sixteen tools sit in two rows of eight', (tester) async {
    await pumpEditor(tester, const Size(390, 844));
    final tops = <double>{};
    final lefts = <double>{};
    for (final tool in tools) {
      final rect = tester.getRect(find.byTooltip(tool));
      tops.add(rect.top.roundToDouble());
      lefts.add(rect.left.roundToDouble());
    }
    expect(tops, hasLength(2));
    expect(lefts, hasLength(8));
  });

  testWidgets('the mode switch hides the toolbar and shows rendered text', (
    tester,
  ) async {
    await pumpEditor(tester, const Size(390, 844));
    expect(find.byType(MarkdownView), findsNothing);
    expect(find.text('预览'), findsOneWidget);

    await tester.tap(find.byTooltip('切换到预览'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(MarkdownView), findsOneWidget);
    expect(find.byTooltip(tools.first), findsNothing);
    expect(find.text('编辑'), findsOneWidget);

    await tester.tap(find.byTooltip('切换到编辑'));
    await tester.pumpAndSettle();
    expect(find.byTooltip(tools.first), findsOneWidget);
  });

  testWidgets('the editor keeps the toolbar free of document stats', (
    tester,
  ) async {
    await pumpEditor(tester, const Size(390, 844));
    // Word count lives on the read-only detail page, at the end of the text.
    expect(find.textContaining('字数'), findsNothing);
  });

  testWidgets('a checklist line lights up the checklist button', (
    tester,
  ) async {
    await pumpEditor(tester, const Size(390, 844));
    final body = find.byType(TextField).last;
    final controller = tester.widget<TextField>(body).controller!;
    await tester.enterText(body, '- [ ] 核对窑址标本');
    controller.selection = const TextSelection.collapsed(offset: 4);
    await tester.pump();

    Color? tintOf(String tooltip) {
      final box = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byTooltip(tooltip),
          matching: find.byType(AnimatedContainer),
        ),
      );
      return (box.decoration as BoxDecoration?)?.color;
    }

    BoxDecoration decorationOf(String tooltip) {
      final box = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byTooltip(tooltip),
          matching: find.byType(AnimatedContainer),
        ),
      );
      return box.decoration! as BoxDecoration;
    }

    // The checklist button is lit, the bullet button is not: a task row is one
    // state, not two.
    expect(tintOf('任务列表'), isNot(Colors.transparent));
    expect(tintOf('列表'), Colors.transparent);
    // Lit means a tint plus a hairline: the tint alone is nearly invisible in
    // dark mode, which is how this looked broken on device.
    expect(decorationOf('任务列表').border, isNotNull);

    // Drop the editor so its autosave timers are cancelled before teardown.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tapping the checklist button lights it in the same frame', (
    tester,
  ) async {
    await pumpEditor(tester, const Size(390, 844));
    final body = find.byType(TextField).last;
    await tester.enterText(body, '核对窑址标本');
    await tester.pump();

    Color? tintOf(String tooltip) {
      final box = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byTooltip(tooltip),
          matching: find.byType(AnimatedContainer),
        ),
      );
      return (box.decoration as BoxDecoration?)?.color;
    }

    expect(tintOf('任务列表'), Colors.transparent);
    await tester.tap(find.byTooltip('任务列表'));
    await tester.pump();
    final controller = tester.widget<TextField>(body).controller!;
    expect(controller.text, '- [ ] 核对窑址标本');
    expect(tintOf('任务列表'), isNot(Colors.transparent));

    // A second tap turns the row back into plain text and the light goes out.
    await tester.tap(find.byTooltip('任务列表'));
    await tester.pump();
    expect(controller.text, '核对窑址标本');
    expect(tintOf('任务列表'), Colors.transparent);

    await tester.pumpWidget(const SizedBox());
  });
}
