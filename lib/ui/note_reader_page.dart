import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../domain/models/note.dart';

class NoteReaderPage extends StatefulWidget {
  const NoteReaderPage({required this.note, required this.onEdit, super.key});

  final Note note;
  final Future<void> Function() onEdit;

  @override
  State<NoteReaderPage> createState() => _NoteReaderPageState();
}

class _NoteReaderPageState extends State<NoteReaderPage> {
  WebViewController? _webView;

  @override
  void initState() {
    super.initState();
    if (!widget.note.isMarkdown) {
      _webView = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.disabled)
        ..setBackgroundColor(const Color(0xfff6f4eb))
        ..loadHtmlString(_htmlDocument(widget.note.content));
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    return Scaffold(
      appBar: AppBar(
        title: Text(note.title.isEmpty ? '无标题' : note.title),
        actions: [
          if (note.isStarred)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Icon(Icons.star, color: Color(0xff816d32)),
            ),
          IconButton(
            tooltip: '编辑',
            onPressed: () async {
              await widget.onEdit();
              if (context.mounted) Navigator.of(context).pop();
            },
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Metadata(note: note),
          Expanded(
            child: note.isMarkdown
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: SelectableText(
                      note.content,
                      style: const TextStyle(fontSize: 16, height: 1.65),
                    ),
                  )
                : WebViewWidget(controller: _webView!),
          ),
          if (note.tags.isNotEmpty)
            Container(
              color: const Color(0xffebe8dc),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: note.tags
                    .map(
                      (tag) => Chip(
                        label: Text(tag),
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
        ],
      ),
    );
  }

  static String _htmlDocument(String content) => '''<!doctype html>
<html><head><meta name="viewport" content="width=device-width, initial-scale=1">
<style>
body { margin: 20px; color: #222; background: #f6f4eb; font: 16px/1.65 sans-serif;
  overflow-wrap: anywhere; -webkit-user-select: text; user-select: text; }
img, video { max-width: 100%; height: auto; }
pre { overflow-x: auto; padding: 12px; background: #ebe8dc; }
table { max-width: 100%; border-collapse: collapse; }
td, th { border: 1px solid #ccc; padding: 6px; }
</style></head><body>$content</body></html>''';
}

class _Metadata extends StatelessWidget {
  const _Metadata({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xffebe8dc),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Text(
      '${note.isMarkdown ? 'MD' : 'RT'}  ·  修改 ${note.updatedTime}',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall,
    ),
  );
}
