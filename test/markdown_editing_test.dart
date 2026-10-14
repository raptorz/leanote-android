import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gemsnote/ui/markdown_editing.dart';

void main() {
  test('inline formatting preserves surrounding text and selected body', () {
    final result = wrapMarkdown(
      const TextEditingValue(
        text: '你好 world!',
        selection: TextSelection(baseOffset: 8, extentOffset: 3),
      ),
      '**',
    );
    expect(result.text, '你好 **world**!');
    expect(result.selection.textInside(result.text), 'world');
    expect(result.composing, TextRange.empty);
  });
  test('collapsed and invalid selections are safe', () {
    final result = wrapMarkdown(
      const TextEditingValue(
        text: 'A',
        selection: TextSelection.collapsed(offset: 1),
      ),
      '`',
    );
    expect(result.text, 'A``');
    expect(result.selection.baseOffset, 2);
    expect(wrapMarkdown(const TextEditingValue(text: 'A'), '**').text, 'A****');
    expect(
      wrapMarkdown(
        const TextEditingValue(
          text: 'A',
          selection: TextSelection.collapsed(offset: 99),
        ),
        '*',
      ).text,
      'A**',
    );
  });
  test(
    'line formatting affects full selected lines, not trailing next line',
    () {
      final result = prefixMarkdownLines(
        const TextEditingValue(
          text: 'one\ntwo\nthree',
          selection: TextSelection(baseOffset: 1, extentOffset: 8),
        ),
        '- ',
      );
      expect(result.text, '- one\n- two\nthree');
      expect(result.selection.textInside(result.text), '- one\n- two');
      final caret = prefixMarkdownLines(
        const TextEditingValue(
          text: 'one\ntwo',
          selection: TextSelection.collapsed(offset: 5),
        ),
        '# ',
      );
      expect(caret.text, 'one\n# two');
      expect(caret.selection.baseOffset, 7);
      expect(prefixMarkdownLines(const TextEditingValue(), '- ').text, '- ');
    },
  );
  test(
    'heading and quote toolbar actions toggle without duplicating prefixes',
    () {
      final initial = const TextEditingValue(
        text: 'one\ntwo\nthree',
        selection: TextSelection(baseOffset: 1, extentOffset: 8),
      );
      final headed = toggleMarkdownPrefixLines(initial, '# ');
      expect(headed.text, '# one\n# two\nthree');
      expect(toggleMarkdownPrefixLines(headed, '# ').text, initial.text);
      final quoted = toggleMarkdownPrefixLines(initial, '> ');
      expect(quoted.text, '> one\n> two\nthree');
      expect(toggleMarkdownPrefixLines(quoted, '> ').text, initial.text);
    },
  );
  test(
    'mixed selection receives one marker per line and removes it on repeat',
    () {
      const value = TextEditingValue(
        text: '- one\ntwo\nthree',
        selection: TextSelection(baseOffset: 0, extentOffset: 9),
      );
      final marked = toggleMarkdownPrefixLines(value, '- ');
      expect(marked.text, '- one\n- two\nthree');
      expect(toggleMarkdownPrefixLines(marked, '- ').text, 'one\ntwo\nthree');
    },
  );
  test(
    'numbered list renumbers selected lines and toggles back to plain text',
    () {
      const value = TextEditingValue(
        text: '7. old\nnew\nafter',
        selection: TextSelection(baseOffset: 0, extentOffset: 11),
      );
      final numbered = toggleMarkdownNumberedLines(value);
      expect(numbered.text, '1. old\n2. new\nafter');
      expect(toggleMarkdownNumberedLines(numbered).text, 'old\nnew\nafter');
    },
  );
  test('caret stays on same text when a line marker is removed', () {
    const value = TextEditingValue(
      text: '> hello',
      selection: TextSelection.collapsed(offset: 5),
    );
    final plain = toggleMarkdownPrefixLines(value, '> ');
    expect(plain.text, 'hello');
    expect(plain.selection.baseOffset, 3);
    final again = toggleMarkdownPrefixLines(plain, '> ');
    expect(again.text, '> hello');
    expect(again.selection.baseOffset, 5);
  });
  test(
    'bold and italic toolbar buttons remove their own wrapper on repeat',
    () {
      const value = TextEditingValue(
        text: 'before word after',
        selection: TextSelection(baseOffset: 7, extentOffset: 11),
      );
      final bold = toggleMarkdownWrap(value, '**');
      expect(bold.text, 'before **word** after');
      final plain = toggleMarkdownWrap(bold, '**');
      expect(plain.text, value.text);
      expect(plain.selection.textInside(plain.text), 'word');
      final italic = toggleMarkdownWrap(value, '*');
      expect(italic.text, 'before *word* after');
      expect(toggleMarkdownWrap(italic, '*').text, value.text);
    },
  );
  test('italic on bold text keeps bold markers intact', () {
    const value = TextEditingValue(
      text: '**word**',
      selection: TextSelection(baseOffset: 2, extentOffset: 6),
    );
    final combined = toggleMarkdownWrap(value, '*');
    expect(combined.text, '***word***');
    expect(toggleMarkdownWrap(combined, '*').text, value.text);
    expect(toggleMarkdownWrap(combined, '**').text, '*word*');
  });
  test('inline toggle handles a complete selection and an empty caret', () {
    const complete = TextEditingValue(
      text: 'say **hi** now',
      selection: TextSelection(baseOffset: 4, extentOffset: 10),
    );
    final unwrapped = toggleMarkdownWrap(complete, '**');
    expect(unwrapped.text, 'say hi now');
    expect(unwrapped.selection.textInside(unwrapped.text), 'hi');
    final empty = toggleMarkdownWrap(
      const TextEditingValue(
        text: 'ab',
        selection: TextSelection.collapsed(offset: 1),
      ),
      '**',
    );
    expect(empty.text, 'a****b');
    expect(toggleMarkdownWrap(empty, '**').text, 'ab');
  });
}
