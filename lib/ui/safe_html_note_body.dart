import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import 'cached_markdown_image.dart';
import 'markdown_note_body.dart' show copyNoteText;
import 'note_link_dialog.dart';
import 'spanning_table.dart';
import '../services/note_link_opener.dart';

/// Native HTML preview; optional media callbacks enforce account-scoped access.
/// Unknown wrappers retain their text; active/embedded content is omitted.
class SafeHtmlNoteBody extends StatelessWidget {
  const SafeHtmlNoteBody({
    required this.content,
    this.loadCachedImage,
    this.downloadImage,
    this.canDownloadImage,
    this.linkOpener,
    super.key,
  });

  final String content;
  final NoteLinkOpener? linkOpener;
  final CachedImageLoader? loadCachedImage;
  final Future<Uint8List> Function(Uri)? downloadImage;
  final bool Function(Uri)? canDownloadImage;

  static const _omitted = {
    'script',
    'style',
    'iframe',
    'object',
    'embed',
    'template',
    'head',
    'svg',
    'math',
    'noscript',
    'form',
    'input',
    'button',
    'select',
    'textarea',
  };
  static const _blocks = {
    'p',
    'div',
    'section',
    'article',
    'header',
    'footer',
    'blockquote',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'pre',
    'ul',
    'ol',
    'li',
    'tr',
    'table',
  };

  List<String> _links(List<dom.Node> nodes) {
    final found = <String>{};
    void visit(List<dom.Node> children, int depth) {
      if (depth >= 64 || found.length >= 100) return;
      for (final node in children) {
        if (found.length >= 100) return;
        if (node is! dom.Element || _omitted.contains(node.localName)) continue;
        if (node.localName == 'a') {
          final href = node.attributes['href'];
          if (href != null && href.isNotEmpty) found.add(href);
        }
        visit(node.nodes, depth + 1);
      }
    }

    visit(nodes, 0);
    return found.toList();
  }

  List<InlineSpan> _render(
    List<dom.Node> nodes, {
    int depth = 0,
    bool pre = false,
    List<dom.Element>? images,
    List<dom.Element>? tables,
    double imageWidth = 0,
  }) {
    final spans = <InlineSpan>[];
    var listIndex = 0;
    for (final node in nodes) {
      if (node is dom.Text) {
        spans.add(
          TextSpan(
            text: pre ? node.data : node.data.replaceAll(RegExp(r'\s+'), ' '),
          ),
        );
        continue;
      }
      if (node is! dom.Element) continue;
      final tag = node.localName ?? '';
      if (_omitted.contains(tag)) continue;
      // Avoid unbounded recursion for hostile or accidentally deeply nested HTML.
      if (depth >= 64) {
        spans.add(const TextSpan(text: '[嵌套内容过深，请查看原文]'));
        continue;
      }
      if (tag == 'table' && tables != null) {
        final grid = HtmlTableGrid.parse(node);
        if (grid != null && grid.hasSpans) {
          tables.add(node);
          spans.add(const TextSpan(text: '\n'));
          spans.add(
            WidgetSpan(
              child: SizedBox(
                width: imageWidth,
                child: _spanningTable(
                  node,
                  grid,
                  imageWidth,
                  images,
                  depth + 1,
                ),
              ),
            ),
          );
          spans.add(const TextSpan(text: '\n'));
          continue;
        }
        final rows = _tableRows(node);
        if (rows != null) {
          tables.add(node);
          spans.add(const TextSpan(text: '\n'));
          spans.add(
            WidgetSpan(
              child: SizedBox(
                width: imageWidth,
                child: _table(node, rows, imageWidth, images, depth + 1),
              ),
            ),
          );
          spans.add(const TextSpan(text: '\n'));
          continue;
        }
        spans.add(const TextSpan(text: '\n[复杂或大型表格按文字显示，可查看原文]\n'));
      }
      if (tag == 'img' || tag == 'video' || tag == 'audio') {
        final collected = tag == 'img' && images != null && images.length < 100;
        if (collected) {
          images.add(node);
          spans.add(const TextSpan(text: '\n'));
          spans.add(
            WidgetSpan(
              child: SizedBox(width: imageWidth, child: _image(node)),
            ),
          );
          spans.add(const TextSpan(text: '\n'));
          continue;
        }
        final alt = node.attributes['alt'];
        spans.add(
          TextSpan(
            text: '[媒体尚未缓存${alt == null || alt.isEmpty ? '' : '：$alt'}]',
          ),
        );
        continue;
      }
      if (tag == 'br' || tag == 'hr') {
        spans.add(TextSpan(text: tag == 'br' ? '\n' : '\n────────\n'));
        continue;
      }
      if (_blocks.contains(tag)) spans.add(const TextSpan(text: '\n'));
      if (tag == 'li') {
        final parent = node.parentNode;
        listIndex++;
        spans.add(
          TextSpan(
            text: parent is dom.Element && parent.localName == 'ol'
                ? '$listIndex. '
                : '• ',
          ),
        );
      }
      final heading = RegExp(r'^h[1-6]$').hasMatch(tag);
      final style = TextStyle(
        fontWeight: heading || tag == 'b' || tag == 'strong' || tag == 'th'
            ? FontWeight.bold
            : null,
        fontStyle: tag == 'i' || tag == 'em' || tag == 'blockquote'
            ? FontStyle.italic
            : null,
        fontFamily: tag == 'code' || tag == 'pre' ? 'monospace' : null,
        fontSize: heading ? 26 - int.parse(tag.substring(1)) * 2.0 : null,
        decoration: tag == 's' || tag == 'del'
            ? TextDecoration.lineThrough
            : tag == 'u'
            ? TextDecoration.underline
            : null,
      );
      spans.add(
        TextSpan(
          style: style,
          children: _render(
            node.nodes,
            depth: depth + 1,
            pre: pre || tag == 'pre',
            images: images,
            tables: tag == 'table' ? null : tables,
            imageWidth: imageWidth,
          ),
        ),
      );
      // Addresses are selectable text only, never executable links.
      if (tag == 'a') {
        final href = node.attributes['href'];
        if (href != null && href.isNotEmpty) {
          spans.add(TextSpan(text: ' ($href)'));
        }
      }
      if (tag == 'td' || tag == 'th') spans.add(const TextSpan(text: ' | '));
      if (_blocks.contains(tag)) spans.add(const TextSpan(text: '\n'));
    }
    return spans;
  }

  List<List<dom.Element>>? _tableRows(dom.Element table) {
    if (table.querySelector('table') != null) return null;
    final rows = <List<dom.Element>>[];
    var cellCount = 0;
    final rowNodes = <dom.Element>[];
    for (final child in table.children) {
      if (child.localName == 'tr') {
        rowNodes.add(child);
      } else if ({'thead', 'tbody', 'tfoot'}.contains(child.localName)) {
        if (child.children.any((node) => node.localName != 'tr')) return null;
        rowNodes.addAll(child.children);
      } else if (child.localName != 'caption') {
        return null;
      }
    }
    for (final row in rowNodes) {
      final cells = row.children;
      if (cells.isEmpty ||
          cells.length > 20 ||
          cells.any(
            (cell) =>
                !{'td', 'th'}.contains(cell.localName) ||
                (cell.attributes['colspan'] ?? '1') != '1' ||
                (cell.attributes['rowspan'] ?? '1') != '1',
          )) {
        return null;
      }
      rows.add(cells);
      cellCount += cells.length;
      if (rows.length > 100 || cellCount > 1000) return null;
    }
    return rows.isEmpty ? null : rows;
  }

  Widget _spanningTable(
    dom.Element table,
    HtmlTableGrid grid,
    double width,
    List<dom.Element>? images,
    int depth,
  ) {
    final cellWidth = (width / grid.columns).clamp(140.0, 320.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final caption in table.children.where(
          (node) => node.localName == 'caption',
        ))
          Text.rich(
            TextSpan(children: _render(caption.nodes, depth: depth)),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SpanningTable(
            grid: grid,
            columnWidth: cellWidth,
            children: [
              for (final cell in grid.cells)
                Container(
                  alignment: Alignment.topLeft,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cell.element?.localName == 'th'
                        ? const Color(0xffe5eee8)
                        : Colors.transparent,
                    border: Border.all(
                      color: const Color(0xff527b68),
                      width: 0.5,
                    ),
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: _render(
                        cell.element?.nodes ?? [],
                        depth: depth + 1,
                        images: images,
                        imageWidth: cellWidth * cell.columns - 16,
                      ),
                    ),
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.65,
                      fontWeight: cell.element?.localName == 'th'
                          ? FontWeight.bold
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _table(
    dom.Element table,
    List<List<dom.Element>> rows,
    double availableWidth,
    List<dom.Element>? images,
    int depth,
  ) {
    final columns = rows.fold<int>(
      0,
      (max, row) => row.length > max ? row.length : max,
    );
    final cellWidth = (availableWidth / columns).clamp(140.0, 320.0);
    final caption = table.children.where((node) => node.localName == 'caption');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final node in caption)
          Text.rich(
            TextSpan(children: _render(node.nodes, depth: depth)),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: FixedColumnWidth(cellWidth),
            border: TableBorder.all(color: const Color(0xff527b68)),
            defaultVerticalAlignment: TableCellVerticalAlignment.top,
            children: [
              for (final row in rows)
                TableRow(
                  children: [
                    for (var index = 0; index < columns; index++)
                      if (index >= row.length)
                        const SizedBox()
                      else
                        ColoredBox(
                          color: row[index].localName == 'th'
                              ? const Color(0xffe5eee8)
                              : Colors.transparent,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text.rich(
                              TextSpan(
                                children: _render(
                                  row[index].nodes,
                                  depth: depth + 1,
                                  images: images,
                                  imageWidth: cellWidth - 16,
                                ),
                              ),
                              style: TextStyle(
                                fontSize: 16,
                                height: 1.65,
                                fontWeight: row[index].localName == 'th'
                                    ? FontWeight.bold
                                    : null,
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final images = <dom.Element>[];
        final tables = <dom.Element>[];
        final nodes = html.parseFragment(content).nodes;
        final links = _links(nodes);
        final spans = _render(
          nodes,
          images: loadCachedImage == null ? null : images,
          tables: tables,
          imageWidth: constraints.maxWidth,
        );
        final text = TextSpan(
          style: DefaultTextStyle.of(context).style
              .copyWith(fontSize: 16, height: 1.65),
          children: spans,
        );
        return SingleChildScrollView(
          // SelectableText supports only TextSpans. SelectionArea with Text.rich
          // retains native text selection around embedded images and tables.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              images.isEmpty && tables.isEmpty
                  ? SelectableText.rich(text)
                  : SelectionArea(child: Text.rich(text)),
              if (links.isNotEmpty)
                ExpansionTile(
                  title: Text('正文链接（${links.length}）'),
                  subtitle: const Text('查看地址后选择复制或外部打开'),
                  children: [
                    for (final href in links)
                      ListTile(
                        leading: const Icon(Icons.link),
                        title: Text(
                          href,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (dialogContext) => NoteLinkDialog(
                            href: href,
                            opener: linkOpener,
                            onCopy: () => copyNoteText(dialogContext, href),
                          ),
                        ),
                      ),
                    if (links.length == 100)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('最多列出 100 个不同地址，其余可查看原文。'),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    ),
  );

  Widget _image(dom.Element element) {
    final uri = Uri.tryParse(element.attributes['src'] ?? '');
    if (uri == null || uri.toString().isEmpty) return const Text('图片地址无效');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CachedMarkdownImage(
        uri: uri,
        alt: element.attributes['alt'],
        load: loadCachedImage!,
        download: downloadImage != null && canDownloadImage?.call(uri) == true
            ? () => downloadImage!(uri)
            : null,
      ),
    );
  }
}
