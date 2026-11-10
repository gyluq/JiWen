import 'package:flutter_test/flutter_test.dart';
import 'package:jiwen/util/markdown_parser.dart';

void main() {
  test('an image line right after text becomes its own block', () {
    final document = parseMarkdown('正文\n![](attachments/a.jpg)\n');
    expect(document.blocks, hasLength(2));
    expect(document.blocks.first, isA<MdParagraph>());
    final imageBlock = document.blocks.last as MdParagraph;
    expect(imageBlock.children, hasLength(1));
    expect((imageBlock.children.single as MdImage).url, 'attachments/a.jpg');
  });

  test('an image between paragraphs stays a media block', () {
    final document = parseMarkdown('第一段\n\n![](attachments/a.jpg)\n\n第二段');
    expect(document.blocks, hasLength(3));
    final imageBlock = document.blocks[1] as MdParagraph;
    expect(imageBlock.children.single, isA<MdImage>());
  });

  test('an image inside a text line stays inline', () {
    final document = parseMarkdown('看图 ![](attachments/a.jpg) 结尾');
    expect(document.blocks, hasLength(1));
    final paragraph = document.blocks.single as MdParagraph;
    expect(paragraph.children.whereType<MdImage>(), hasLength(1));
  });

  test('an image line inside a code block is not split out', () {
    final document = parseMarkdown('```\n![](attachments/a.jpg)\n```');
    expect(document.blocks, hasLength(1));
    expect(document.blocks.single, isA<MdCodeBlock>());
  });

  test('outline keeps H1-H3 headings and their block indexes', () {
    final document = parseMarkdown('# 一\n正文\n## 二\n### 三\n```\n## 代码\n```');
    final outline = extractOutline(document);
    expect(outline.map((entry) => entry.text), ['一', '二', '三']);
    expect(outline.map((entry) => entry.level), [1, 2, 3]);
    expect(outline.map((entry) => entry.blockIndex), [0, 2, 3]);
  });

  test('outline ignores headings with no visible text', () {
    final document = parseMarkdown('# **一**\n## \n###\n');
    final outline = extractOutline(document);
    expect(outline.map((entry) => entry.text), ['一']);
  });

  test('first search hit reports the block that contains it', () {
    final document = parseMarkdown('# 标题\n\n正文关键词\n\n结尾');
    expect(firstMatchBlock(document, '关键词'), 1);
    expect(firstMatchBlock(document, '不存在'), isNull);
    expect(firstMatchBlock(document, '  '), isNull);
  });

  group('table', () {
    test('parses header, rows and alignment', () {
      final document = parseMarkdown(
        '| 窑口 | 釉色 | 厚度 |\n'
        '| :--- | :---: | ---: |\n'
        '| 汝窑 | 天青 | 0.4 |\n'
        '| 龙泉 | 梅子青 | 1.2 |',
      );
      final table = document.blocks.single as MdTableBlock;
      expect(table.columnCount, 3);
      expect(table.aligns, [
        MdColumnAlign.left,
        MdColumnAlign.center,
        MdColumnAlign.right,
      ]);
      expect(inlinePlainText(table.header[0]), '窑口');
      expect(table.rows, hasLength(2));
      expect(inlinePlainText(table.rows[1][1]), '梅子青');
    });

    test('outer pipes are optional and short rows are padded', () {
      final document = parseMarkdown('a | b\n--- | ---\n1 |');
      final table = document.blocks.single as MdTableBlock;
      expect(table.rows.single, hasLength(2));
      expect(inlinePlainText(table.rows.single[0]), '1');
      expect(inlinePlainText(table.rows.single[1]), '');
    });

    test('a table directly under text is its own block', () {
      final document = parseMarkdown(
        '说明如下\n| a | b |\n| --- | --- |\n| 1 | 2 |',
      );
      expect(document.blocks, hasLength(2));
      expect(document.blocks.first, isA<MdParagraph>());
      expect(document.blocks.last, isA<MdTableBlock>());
    });

    test('a pipe line without a delimiter row stays text', () {
      final document = parseMarkdown('a | b\nc | d');
      expect(document.blocks.single, isA<MdParagraph>());
    });

    test('cells keep inline formatting', () {
      final document = parseMarkdown('| **粗** |\n| --- |');
      final table = document.blocks.single as MdTableBlock;
      expect(table.header.single.single, isA<MdStrong>());
    });
  });

  group('divider', () {
    test('accepts dashes, asterisks and underscores', () {
      final document = parseMarkdown('a\n\n---\n\n***\n\n- - -\n\n___');
      expect(document.blocks.whereType<MdDividerBlock>(), hasLength(4));
      expect(document.blocks.whereType<MdParagraph>(), hasLength(1));
    });

    test('a bullet item is not a divider', () {
      final document = parseMarkdown('- item\n* item2');
      expect(document.blocks.single, isA<MdListBlock>());
    });
  });

  group('task list', () {
    test('reads checked and unchecked items', () {
      final document = parseMarkdown('- [ ] 查资料\n- [x] 写笔记');
      final tasks = document.blocks.single as MdTaskListBlock;
      expect(tasks.items, hasLength(2));
      expect(tasks.items.first.checked, isFalse);
      expect(tasks.items.last.checked, isTrue);
      expect(inlinePlainText(tasks.items.last.children), '写笔记');
    });

    test('a task list is not folded into a neighbouring bullet list', () {
      final document = parseMarkdown('- a\n- [ ] b');
      expect(document.blocks.first, isA<MdListBlock>());
      expect(document.blocks.last, isA<MdTaskListBlock>());
    });

    test('task rows remember the line they came from', () {
      final document = parseMarkdown('# 清单\n\n- [ ] 查资料\n- [x] 写笔记\n\n正文');
      final tasks = document.blocks.whereType<MdTaskListBlock>().single;
      expect(tasks.items.map((item) => item.line), [2, 3]);
    });
  });

  group('strikethrough', () {
    test('wraps text in MdStrike', () {
      final document = parseMarkdown('价格 ~~128~~ 现价');
      final paragraph = document.blocks.single as MdParagraph;
      final strike = paragraph.children.whereType<MdStrike>();
      expect(strike, hasLength(1));
      expect(inlinePlainText(strike.single.children), '128');
    });

    test('a lone pair of tildes stays literal', () {
      final document = parseMarkdown('~~~~');
      expect(document.blocks.single, isA<MdParagraph>());
    });
  });

  test('underscore emphasis stays literal text', () {
    final document = parseMarkdown('_斜_ 与 __粗__');
    final paragraph = document.blocks.single as MdParagraph;
    expect(paragraph.children.single, isA<MdText>());
    expect(inlinePlainText(paragraph.children), '_斜_ 与 __粗__');
  });
}
