import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiwen/util/markdown_edit.dart';

TextEditingValue _value(String text, [int? start, int? end]) {
  final base = start ?? text.length;
  final extent = end ?? base;
  return TextEditingValue(
    text: text,
    selection: TextSelection(baseOffset: base, extentOffset: extent),
  );
}

void main() {
  group('inline', () {
    test('bold inserts a selected placeholder', () {
      final result = toggleBold(_value('hello'));
      expect(result.text, 'hello**粗体**');
      expect(result.selection.start, 7);
      expect(result.selection.end, 9);
    });

    test('bold toggles off around the placeholder', () {
      final result = toggleBold(_value('**粗体**', 2, 4));
      expect(result.text, '粗体');
      expect(result.selection.start, 0);
      expect(result.selection.end, 2);
    });

    test('bold removes empty markers at the caret', () {
      final result = toggleBold(_value('****', 2, 2));
      expect(result.text, '');
      expect(result.selection.isCollapsed, isTrue);
      expect(result.selection.start, 0);
    });

    test('bold strips markers included in the selection', () {
      final result = toggleBold(_value('**abc**', 0, 7));
      expect(result.text, 'abc');
      expect(result.selection.start, 0);
      expect(result.selection.end, 3);
    });

    test('bold wraps and unwraps a selection', () {
      final wrapped = toggleBold(_value('abc', 0, 3));
      expect(wrapped.text, '**abc**');
      expect(wrapped.selection.start, 2);
      expect(wrapped.selection.end, 5);

      final unwrapped = toggleBold(_value('**abc**', 2, 5));
      expect(unwrapped.text, 'abc');
      expect(unwrapped.selection.start, 0);
      expect(unwrapped.selection.end, 3);
    });

    test('italic does not eat a bold marker', () {
      final result = toggleBold(_value('**abc**', 2, 5));
      expect(result.text, 'abc');
    });

    test('link selects the url placeholder', () {
      final result = insertLink(_value('see '));
      expect(result.text, 'see [链接文字](https://)');
      expect(
        result.text.substring(result.selection.start, result.selection.end),
        'https://',
      );
    });
  });

  group('lines', () {
    test('heading cycles h1 to h3 to none', () {
      var value = _value('title');
      value = cycleHeading(value).value;
      expect(value.text, '# title');
      value = cycleHeading(value).value;
      expect(value.text, '## title');
      value = cycleHeading(value).value;
      expect(value.text, '### title');
      value = cycleHeading(value).value;
      expect(value.text, 'title');
    });

    test('list toggles bullets on selected lines', () {
      final added = toggleList(_value('a\nb', 0, 3));
      expect(added.text, '- a\n- b');

      final removed = toggleList(_value('- a\n- b', 0, 7));
      expect(removed.text, 'a\nb');
    });

    test('code block wraps and unwraps the current line', () {
      final wrapped = toggleCodeBlock(_value('abc', 0, 0));
      expect(wrapped.text, '```\nabc\n```');
      expect(wrapped.selection.start, 4);

      final unwrapped = toggleCodeBlock(_value('```\nabc\n```', 4, 4));
      expect(unwrapped.text, 'abc');
    });

    test('code block on an empty line leaves a blank body', () {
      final result = toggleCodeBlock(_value(''));
      expect(result.text, '```\n\n```');
      expect(result.selection.start, 4);
    });
  });

  group('state', () {
    test('detects heading and list state on the current line', () {
      final heading = inspectMarkdown(_value('# title\n\nbody', 6, 6));
      expect(heading.headingLevel, 1);

      final list = inspectMarkdown(_value('- item', 4, 4));
      expect(list.inList, isTrue);
      expect(list.headingLevel, 0);
    });

    test('detects bold state at the caret', () {
      final state = inspectMarkdown(_value('a **bold** b', 7, 7));
      expect(state.bold, isTrue);
      expect(state.italic, isFalse);
    });

    test('detects code block state', () {
      final state = inspectMarkdown(_value('```\nabc\n```', 5, 5));
      expect(state.inCodeBlock, isTrue);
    });
  });

  group('list continuation', () {
    const formatter = ListContinuationFormatter();

    TextEditingValue enter(String before, String after) {
      final oldValue = _value(before + after, before.length, before.length);
      final newValue = _value(
        '$before\n$after',
        before.length + 1,
        before.length + 1,
      );
      return formatter.formatEditUpdate(oldValue, newValue);
    }

    test('continues a bullet', () {
      final result = enter('- item', '');
      expect(result.text, '- item\n- ');
      expect(result.selection.start, 9);
    });

    test('continues an ordered item', () {
      final result = enter('3. item', '');
      expect(result.text, '3. item\n4. ');
    });

    test('splits the item text at the caret', () {
      final result = enter('- one', ' two');
      expect(result.text, '- one\n-  two');
    });

    test('second enter exits the list', () {
      final result = enter('- ', '');
      expect(result.text, '\n');
      expect(result.selection.start, 0);
    });

    test('plain lines are untouched', () {
      final result = enter('text', '');
      expect(result.text, 'text\n');
    });
  });
}
