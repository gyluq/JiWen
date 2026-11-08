import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiwen/data/backup.dart';
import 'package:jiwen/data/exporter.dart';
import 'package:jiwen/models/note.dart';
import 'package:jiwen/models/tag.dart';
import 'package:jiwen/util/text_import.dart';

void main() {
  group('batch text import', () {
    test('two blank lines separate notes but paragraphs stay together', () {
      final chunks = splitImportText(
        '第一段\n\n同一条笔记的第二段\n\n\n第二条笔记',
        ImportSeparator.blankLines,
      );
      expect(chunks, ['第一段\n\n同一条笔记的第二段', '第二条笔记']);
    });

    test('dashes on their own line separate notes', () {
      final chunks = splitImportText(
        '---\n第一条\n---\n第二条\n---',
        ImportSeparator.rule,
      );
      expect(chunks, ['第一条', '第二条']);
    });

    test('custom delimiter splits literally', () {
      final chunks = splitImportText(
        'A###B###C',
        ImportSeparator.custom,
        customDelimiter: '###',
      );
      expect(chunks, ['A', 'B', 'C']);
    });

    test('empty custom delimiter keeps one note', () {
      final chunks = splitImportText(
        'A\nB',
        ImportSeparator.custom,
      );
      expect(chunks, ['A\nB']);
    });

    test('title drops a markdown heading and body keeps the rest', () {
      const chunk = '## 标题\n正文第一行\n正文第二行';
      expect(importTitleOf(chunk), '标题');
      expect(importBodyOf(chunk), '正文第一行\n正文第二行');
    });

    test('body is empty for a single-line chunk', () {
      expect(importTitleOf('只有一行'), '只有一行');
      expect(importBodyOf('只有一行'), '');
    });
  });

  group('backup bundle', () {
    Map<String, Object?> payload() => {
      'notes': [
        {'id': 'n1', 'title': 't', 'body': 'b'},
      ],
    };

    test('zip bundle carries the document and image bytes', () {
      final archive = Archive();
      final document = utf8.encode(jsonEncode(payload()));
      archive.addFile(
        ArchiveFile('backup.json', document.length, document),
      );
      const image = [1, 2, 3];
      archive.addFile(ArchiveFile('attachments/a.jpg', 3, image));

      final bundle = BackupService.instance.decodeBundle(
        'jiwen_backup.zip',
        ZipEncoder().encodeBytes(archive),
      );
      expect(bundle.payload['notes'], hasLength(1));
      expect(bundle.files['attachments/a.jpg'], image);
    });

    test('legacy json bundle has no files', () {
      final bundle = BackupService.instance.decodeBundle(
        'jiwen_backup.json',
        utf8.encode(jsonEncode(payload())),
      );
      expect(bundle.payload['notes'], hasLength(1));
      expect(bundle.files, isEmpty);
    });

    test('zip without backup.json is rejected', () {
      final archive = Archive();
      archive.addFile(ArchiveFile('attachments/a.jpg', 1, [1]));
      expect(
        () => BackupService.instance.decodeBundle(
          'jiwen_backup.zip',
          ZipEncoder().encodeBytes(archive),
        ),
        throwsFormatException,
      );
    });
  });

  group('markdown export', () {
    Note note({
      String title = '测试笔记',
      String body = '正文',
      NoteStatus status = NoteStatus.todo,
    }) {
      return Note(
        id: 'note-1',
        title: title,
        body: body,
        status: status,
        createdAt: 0,
        updatedAt: 0,
      );
    }

    test('front matter carries title, tags and status', () {
      final markdown = NoteExporter.instance.markdownFor(
        note(status: NoteStatus.done),
        tags: [Tag(id: 't1', name: '瓷器')],
      );
      expect(markdown, contains('title: "测试笔记"'));
      expect(markdown, contains('status: 已解答'));
      expect(markdown, contains('tags: ["瓷器"]'));
      expect(markdown, contains('# 测试笔记'));
    });

    test('body follows the front matter', () {
      final markdown = NoteExporter.instance.markdownFor(note(body: '- 一条'));
      expect(markdown, contains('---\n\n# 测试笔记\n\n- 一条'));
    });

    test('empty title falls back to 无标题', () {
      final markdown = NoteExporter.instance.markdownFor(note(title: ''));
      expect(markdown, contains('title: "无标题"'));
      expect(markdown, isNot(contains('\n# 无标题')));
    });

    test('zip export rewrites attachment paths to assets', () {
      final markdown = NoteExporter.instance.markdownFor(
        note(body: '![](attachments/a.jpg)'),
        rewriteAssets: true,
      );
      expect(markdown, contains('![](assets/a.jpg)'));
    });

    test('single export keeps the private attachment path', () {
      final markdown = NoteExporter.instance.markdownFor(
        note(body: '![](attachments/a.jpg)'),
      );
      expect(markdown, contains('![](attachments/a.jpg)'));
    });
  });
}
