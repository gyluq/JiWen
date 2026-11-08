import 'package:flutter_test/flutter_test.dart';
import 'package:jiwen/util/search_highlight.dart';

void main() {
  group('highlight runs', () {
    test('splits text around every keyword hit', () {
      final runs = highlightRuns('咖啡因影响睡眠，咖啡因代谢慢', '咖啡因');
      expect(runs.map((run) => run.text).toList(), [
        '咖啡因',
        '影响睡眠，',
        '咖啡因',
        '代谢慢',
      ]);
      expect(runs.map((run) => run.isHit).toList(), [true, false, true, false]);
    });

    test('ignores case for latin keywords', () {
      final runs = highlightRuns('Flutter and flutter', 'FLUTTER');
      expect(runs.where((run) => run.isHit).length, 2);
      expect(runs.first.text, 'Flutter');
    });

    test('returns one plain run when the keyword is empty', () {
      final runs = highlightRuns('一段文字', '   ');
      expect(runs, hasLength(1));
      expect(runs.single.isHit, isFalse);
    });

    test('missing keyword leaves the text untouched', () {
      final runs = highlightRuns('一段文字', '不存在');
      expect(runs.single.text, '一段文字');
      expect(runs.single.isHit, isFalse);
    });
  });

  group('plain text excerpt', () {
    test('drops link targets and keeps labels', () {
      final body =
          '# 标题\n\n看 [文档](https://example.com) 与 ![截图](attachments/a.png) 结束';
      expect(markdownToPlainText(body), '标题 看 文档 与 截图 结束');
    });

    test('strips emphasis markers and list bullets', () {
      expect(markdownToPlainText('- **重点**\n- `code`'), '重点 code');
    });

    test('an image with no alt text leaves no reference behind', () {
      expect(markdownToPlainText('前 ![](attachments/a.png) 后'), '前 后');
    });
  });

  group('search snippet', () {
    test('keeps the head when the hit is near the start', () {
      final body = '咖啡因会抑制腺苷受体，从而让人更清醒。';
      expect(searchSnippet(body, '咖啡因'), body);
    });

    test('slides the window around a late hit', () {
      final body = '${'前置内容' * 20}目标关键词${'后置内容' * 20}';
      final snippet = searchSnippet(body, '目标关键词', maxLength: 40);
      expect(snippet.contains('目标关键词'), isTrue);
      expect(snippet.startsWith('…'), isTrue);
      expect(snippet.endsWith('…'), isTrue);
      expect(snippet.length, lessThanOrEqualTo(42));
    });

    test('falls back to the head when nothing matches', () {
      final body = '${'正文' * 30}结尾';
      final snippet = searchSnippet(body, '缺失', maxLength: 20);
      expect(snippet, '${body.substring(0, 20)}…');
    });

    test('collapses whitespace before slicing', () {
      final snippet = searchSnippet('第一行\n\n第二行', '第二行');
      expect(snippet, '第一行 第二行');
    });
  });
}
