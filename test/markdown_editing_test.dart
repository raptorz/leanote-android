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
}
