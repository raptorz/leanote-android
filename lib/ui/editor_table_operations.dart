import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import 'visual_html_policy.dart';

enum TableOperation { addRow, addColumn, removeRow, removeColumn }

/// Transform a snapshot, never the live editor. Reject unsupported shapes
/// without silently dropping content, captions, or section boundaries.
String changeEditorTable(
  String source,
  int rowIndex,
  int columnIndex,
  TableOperation operation,
) {
  if (!supportsVisualHtml(source)) throw const FormatException('不支持此表格格式');
  final fragment = html.parseFragment(source);
  if (fragment.children.length != 1 ||
      fragment.children.single.localName != 'table') {
    throw const FormatException('请选择表格单元格');
  }
  final table = fragment.children.single;
  if (fragment.nodes.any(
    (node) => node != table && (node is! Text || node.data.trim().isNotEmpty),
  )) {
    throw const FormatException('表格快照包含额外内容');
  }
  final rows = table.querySelectorAll('tr');
  if (table.querySelector('table') != null ||
      rows.isEmpty ||
      rows.length > 20) {
    throw const FormatException('仅支持最多 20 行的基础表格');
  }
  final columns = rows.first.children.length;
  if (columns < 1 ||
      columns > 10 ||
      rows.any(
        (row) =>
            row.children.length != columns ||
            row.children.any((cell) => !{'td', 'th'}.contains(cell.localName)),
      )) {
    throw const FormatException('仅支持列数一致、最多 10 列的基础表格');
  }
  if (rowIndex < 0 ||
      rowIndex >= rows.length ||
      columnIndex < 0 ||
      columnIndex >= columns) {
    throw const FormatException('单元格位置已失效，请重新选择');
  }
  Element emptyCell(String tag) => Element.tag(tag)..append(Element.tag('br'));
  switch (operation) {
    case TableOperation.addRow:
      if (rows.length == 20) throw const FormatException('最多支持 20 行');
      final row = rows[rowIndex];
      final newRow = Element.tag('tr');
      for (final cell in row.children) {
        newRow.append(emptyCell(cell.localName!));
      }
      row.parentNode!.nodes.insert(
        row.parentNode!.nodes.indexOf(row) + 1,
        newRow,
      );
    case TableOperation.addColumn:
      if (columns == 10) throw const FormatException('最多支持 10 列');
      for (final row in rows) {
        final cell = row.children[columnIndex];
        row.nodes.insert(
          row.nodes.indexOf(cell) + 1,
          emptyCell(cell.localName!),
        );
      }
    case TableOperation.removeRow:
      if (rows.length == 1) throw const FormatException('不能删除最后一行');
      rows[rowIndex].remove();
    case TableOperation.removeColumn:
      if (columns == 1) throw const FormatException('不能删除最后一列');
      for (final row in rows) {
        row.children[columnIndex].remove();
      }
  }
  return table.outerHtml;
}
