import 'package:flutter/services.dart';

import 'visual_html_policy.dart';

TextSelection _selection(TextEditingValue value) {
  final selection = value.selection;
  if (!selection.isValid || selection.end > value.text.length) {
    return TextSelection.collapsed(offset: value.text.length);
  }
  return selection;
}

TextEditingValue wrapMarkdown(TextEditingValue value, String marker) {
  final selection = _selection(value);
  final selected = value.text.substring(selection.start, selection.end);
  return TextEditingValue(
    text: value.text.replaceRange(
      selection.start,
      selection.end,
      '$marker$selected$marker',
    ),
    selection: TextSelection(
      baseOffset: selection.start + marker.length,
      extentOffset: selection.end + marker.length,
    ),
  );
}

TextEditingValue prefixMarkdownLines(TextEditingValue value, String prefix) {
  return _prefixLines(value, (_) => prefix);
}

TextEditingValue numberMarkdownLines(TextEditingValue value) =>
    _prefixLines(value, (index) => '${index + 1}. ');

TextEditingValue _prefixLines(
  TextEditingValue value,
  String Function(int) prefix,
) {
  final selection = _selection(value);
  final start = value.text.substring(0, selection.start).lastIndexOf('\n') + 1;
  // A selection ending just after a newline does not include the next line.
  final selectedEnd =
      !selection.isCollapsed &&
          selection.end > 0 &&
          value.text[selection.end - 1] == '\n'
      ? selection.end - 1
      : selection.end;
  final nextNewline = value.text.indexOf('\n', selectedEnd);
  final end = nextNewline < 0 ? value.text.length : nextNewline;
  final lines = value.text.substring(start, end).split('\n');
  final replacement = List.generate(
    lines.length,
    (index) => '${prefix(index)}${lines[index]}',
  ).join('\n');
  return TextEditingValue(
    text: value.text.replaceRange(start, end, replacement),
    selection: selection.isCollapsed
        ? TextSelection.collapsed(offset: selection.start + prefix(0).length)
        : TextSelection(
            baseOffset: start,
            extentOffset: start + replacement.length,
          ),
  );
}

TextEditingValue insertMarkdownLink(TextEditingValue value, String url) {
  if (!isSafeEditorLink(url)) throw ArgumentError('Unsupported link');
  final selection = _selection(value);
  final label = selection.isCollapsed
      ? url
      : value.text.substring(selection.start, selection.end);
  final escaped = label
      .replaceAll(RegExp(r'\r\n|\r|\n'), ' ')
      .replaceAllMapped(RegExp(r'[\\\[\]*_`<>]'), (match) => '\\${match[0]}');
  final destination = url
      .replaceAll('\\', '%5C')
      .replaceAll('<', '%3C')
      .replaceAll('>', '%3E');
  final replacement = '[$escaped](<$destination>)';
  return TextEditingValue(
    text: value.text.replaceRange(selection.start, selection.end, replacement),
    selection: TextSelection.collapsed(
      offset: selection.start + replacement.length,
    ),
  );
}

TextEditingValue fenceMarkdownCode(TextEditingValue value) {
  final selection = _selection(value);
  final selected = value.text.substring(selection.start, selection.end);
  var fenceSize = 3;
  for (final match in RegExp(r'`+').allMatches(selected)) {
    if (match.group(0)!.length >= fenceSize) {
      fenceSize = match.group(0)!.length + 1;
    }
  }
  final fence = List.filled(fenceSize, '`').join();
  final before = value.text.substring(0, selection.start);
  final after = value.text.substring(selection.end);
  final leading = before.isEmpty || before.endsWith('\n\n')
      ? ''
      : before.endsWith('\n')
      ? '\n'
      : '\n\n';
  final trailing = after.isEmpty || after.startsWith('\n') ? '' : '\n';
  final replacement =
      '$leading$fence\n$selected${selected.endsWith('\n') ? '' : '\n'}$fence\n$trailing';
  final start = selection.start + leading.length + fence.length + 1;
  return TextEditingValue(
    text: value.text.replaceRange(selection.start, selection.end, replacement),
    selection: TextSelection(
      baseOffset: start,
      extentOffset: start + selected.length,
    ),
  );
}
