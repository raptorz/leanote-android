import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

bool isSafeEditorLink(String value) {
  if (value.isEmpty ||
      value.trim() != value ||
      RegExp(r'[\x00-\x20\x7f]').hasMatch(value)) {
    return false;
  }
  final uri = Uri.tryParse(value);
  return uri != null &&
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;
}

/// Eligibility, not sanitization: unsupported markup must remain in source mode.
/// Separate from conflict-copy policy: hyperlinks do not imply safe file copying.
bool supportsVisualHtml(String source) {
  const tags = {
    'p',
    'div',
    'span',
    'br',
    'hr',
    'b',
    'strong',
    'i',
    'em',
    'u',
    's',
    'del',
    'blockquote',
    'pre',
    'code',
    'ul',
    'ol',
    'li',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'a',
  };
  final parser = html.HtmlParser(source);
  final fragment = parser.parseFragment();
  if (parser.errors.isNotEmpty) return false;
  bool safe(dom.Node node, int depth) {
    if (depth > 64) return false;
    if (node is dom.Text) return true;
    if (node is! dom.Element || !tags.contains(node.localName)) return false;
    for (final attribute in node.attributes.entries) {
      if (node.localName != 'a' ||
          attribute.key != 'href' ||
          !isSafeEditorLink(attribute.value)) {
        return false;
      }
    }
    return node.nodes.every((child) => safe(child, depth + 1));
  }

  return fragment.nodes.every((node) => safe(node, 0));
}
