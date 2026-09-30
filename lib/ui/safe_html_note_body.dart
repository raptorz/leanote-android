import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

/// Native text-only HTML preview: no browser, CSS, navigation or resource I/O.
/// Unknown wrappers retain their text; active/embedded content is omitted.
class SafeHtmlNoteBody extends StatelessWidget {
  const SafeHtmlNoteBody({required this.content, super.key});

  final String content;

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

  List<InlineSpan> _render(
    List<dom.Node> nodes, {
    int depth = 0,
    bool pre = false,
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
      if (tag == 'img' || tag == 'video' || tag == 'audio') {
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

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: SelectableText.rich(
      TextSpan(
        style: DefaultTextStyle.of(context).style
            .copyWith(fontSize: 16, height: 1.65),
        children: _render(html.parseFragment(content).nodes),
      ),
    ),
  );
}
