import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiwen/util/markdown_edit.dart';
import 'package:jiwen/widgets/markdown_view.dart';

/// Ticking a box is a text edit, so the view reports the source line it drew
/// and does not try to keep state of its own.
void main() {
  Future<void> pumpView(
    WidgetTester tester,
    String source, {
    ValueChanged<int>? onToggleTask,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownView(source: source, onToggleTask: onToggleTask),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('tapping a row reports the line it came from', (tester) async {
    final taps = <int>[];
    await pumpView(
      tester,
      '前置段落\n\n- [ ] 查资料\n- [ ] 写笔记',
      onToggleTask: taps.add,
    );

    await tester.tap(find.textContaining('写笔记', findRichText: true));
    await tester.pump();

    expect(taps, [3]);
  });

  testWidgets('the whole row is the target, not just the box', (tester) async {
    final taps = <int>[];
    await pumpView(tester, '- [ ] 一端很长的任务描述文字', onToggleTask: taps.add);

    // Tap near the right edge of the row, far from the 16px box.
    final row = tester.getRect(find.textContaining('一端', findRichText: true));
    await tester.tapAt(Offset(row.right - 4, row.center.dy));
    await tester.pump();

    expect(taps, [0]);
  });

  testWidgets('a toggled source renders a tick', (tester) async {
    await pumpView(tester, '- [ ] 查资料');
    expect(find.byIcon(Icons.check_rounded), findsNothing);

    final next = toggleTaskAtLine('- [ ] 查资料', 0)!;
    await pumpView(tester, next);
    expect(next, '- [x] 查资料');
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('without a callback the rows stay read-only', (tester) async {
    await pumpView(tester, '- [ ] 查资料');
    await tester.tap(find.textContaining('查资料', findRichText: true));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
