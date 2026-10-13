import 'package:html/parser.dart' as html;
import 'package:markdown/markdown.dart' as md;

import 'note_image_reference.dart';

/// Images actually represented by a body, excluding code and arbitrary links.
Set<String> bodyImageIds(
  String body, {
  required bool isMarkdown,
  required Uri server,
}) {
  final ids = <String>{};
  void add(String? source) {
    if (source == null || ids.length >= 100) return;
    final uri = Uri.tryParse(source);
    if (uri == null) return;
    final id = cachedImageFileId(uri, server);
    if (id != null) ids.add(id);
  }

  if (isMarkdown) {
    final document = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
    void visit(List<md.Node> nodes, int depth) {
      if (depth >= 64 || ids.length >= 100) return;
      for (final node in nodes) {
        if (node is! md.Element) continue;
        if (node.tag == 'img') add(node.attributes['src']);
        if (node.tag != 'code' && node.tag != 'pre') {
          visit(node.children ?? [], depth + 1);
        }
      }
    }

    visit(document.parseLines(body.split('\n')), 0);
  } else {
    for (final image in html.parseFragment(body).querySelectorAll('img')) {
      add(image.attributes['src']);
      if (ids.length >= 100) break;
    }
  }
  return ids;
}
