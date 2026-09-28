import 'package:flutter/services.dart';

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
  final replacement = lines.map((line) => '$prefix$line').join('\n');
  return TextEditingValue(
    text: value.text.replaceRange(start, end, replacement),
    selection: selection.isCollapsed
        ? TextSelection.collapsed(offset: selection.start + prefix.length)
        : TextSelection(
            baseOffset: start,
            extentOffset: start + replacement.length,
          ),
  );
}
