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

    test('strikethrough wraps and unwraps a selection', () {
      final wrapped = toggleStrike(_value('abc', 0, 3));
      expect(wrapped.text, '~~abc~~');
      expect(wrapped.selection.start, 2);

      final unwrapped = toggleStrike(_value('~~abc~~', 2, 5));
      expect(unwrapped.text, 'abc');
    });

    test('inline code wraps a selection in backticks', () {
      final wrapped = toggleInlineCode(_value('abc', 0, 3));
      expect(wrapped.text, '`abc`');
      expect(wrapped.selection.start, 1);
      expect(wrapped.selection.end, 4);

      final unwrapped = toggleInlineCode(_value('`abc`', 1, 4));
      expect(unwrapped.text, 'abc');
    });

    test('inline code inserts a placeholder at the caret', () {
      final result = toggleInlineCode(_value('x'));
      expect(result.text, 'x`代码`');
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

    test('task list toggles on and off', () {
      final added = toggleTaskList(_value('a\nb', 0, 3));
      expect(added.text, '- [ ] a\n- [ ] b');

      final converted = toggleTaskList(_value('- a'));
      expect(converted.text, '- [ ] a');

      final removed = toggleTaskList(_value('- [ ] a\n- [x] b', 0, 15));
      expect(removed.text, 'a\nb');
    });

    test('task list keeps the line indentation', () {
      final result = toggleTaskList(_value('  a'));
      expect(result.text, '  - [ ] a');
    });

    test('indent and outdent are separate buttons with fixed direction', () {
      final deeper = indentLines(_value('  a', 0, 3));
      expect(deeper.text, '    a');

      final shallower = outdentLines(_value('    a', 0, 5));
      expect(shallower.text, '  a');

      // Already flush left: nothing to strip, no exception.
      final flush = outdentLines(_value('a', 0, 1));
      expect(flush.text, 'a');

      // A single leading space goes away in one tap.
      final single = outdentLines(_value(' a', 0, 2));
      expect(single.text, 'a');

      // Both directions apply to every selected line.
      expect(indentLines(_value('a\n  b', 0, 5)).text, '  a\n    b');
      expect(outdentLines(_value('  a\n    b', 0, 9)).text, 'a\n  b');
    });

    test('divider starts its own paragraph', () {
      final result = insertDivider(_value('abc'));
      expect(result.text, 'abc\n\n---\n');
      expect(result.selection.start, 'abc\n\n---\n'.length);
    });

    test('divider lands on a blank line without extra newlines', () {
      final result = insertDivider(_value('abc\n'));
      expect(result.text, 'abc\n---\n');
    });

    test('table template selects the first header cell', () {
      final result = insertTable(_value(''));
      expect(result.text, '| 列 1 | 列 2 |\n| --- | --- |\n|  |  |\n');
      expect(
        result.text.substring(result.selection.start, result.selection.end),
        '列 1',
      );
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

    test('a checklist line reports task, not bullet', () {
      final task = inspectMarkdown(_value('- [ ] 核对', 6, 6));
      expect(task.inTask, isTrue);
      expect(task.inList, isFalse);

      final bullet = inspectMarkdown(_value('- 核对', 3, 3));
      expect(bullet.inTask, isFalse);
      expect(bullet.inList, isTrue);

      final checked = inspectMarkdown(_value('- [x] 核对', 6, 6));
      expect(checked.inTask, isTrue);
    });

    test('detects strikethrough and inline code at the caret', () {
      final strike = inspectMarkdown(_value('a ~~gone~~ b', 6, 6));
      expect(strike.strike, isTrue);
      expect(strike.bold, isFalse);

      final code = inspectMarkdown(_value('a `x` b', 4, 4));
      expect(code.codeSpan, isTrue);
      expect(code.strike, isFalse);
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

    test('continues a checklist item unchecked', () {
      final result = enter('- [x] done', '');
      expect(result.text, '- [x] done\n- [ ] ');
      expect(result.selection.start, result.text.length);
    });

    test('an empty checklist item exits the list', () {
      final result = enter('- [ ] ', '');
      expect(result.text, '\n');
      expect(result.selection.start, 0);
    });
  });

  group('ticking from the reading view', () {
    test('flips one box and leaves the other lines alone', () {
      const source = '# 清单\n\n- [ ] 一\n- [x] 二\n';
      expect(toggleTaskAtLine(source, 2), '# 清单\n\n- [x] 一\n- [x] 二\n');
      expect(toggleTaskAtLine(source, 3), '# 清单\n\n- [ ] 一\n- [ ] 二\n');
    });

    test('keeps indentation, the bullet and the text after the box', () {
      expect(toggleTaskAtLine('  * [ ] 缩进的任务', 0), '  * [x] 缩进的任务');
      expect(toggleTaskAtLine('* [X] 大写勾', 0), '* [ ] 大写勾');
    });

    test('returns null when the line is not a checklist row', () {
      expect(toggleTaskAtLine('- 普通项目', 0), isNull);
      expect(toggleTaskAtLine('正文 [ ] 不是行首', 0), isNull);
      expect(toggleTaskAtLine('- [ ] 一', 3), isNull);
      expect(toggleTaskAtLine('- [ ] 一', -1), isNull);
    });

    test('survives CRLF line endings', () {
      expect(toggleTaskAtLine('- [ ] 一\r\n- [ ] 二', 1), '- [ ] 一\r\n- [x] 二');
    });
  });
}
