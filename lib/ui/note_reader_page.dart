import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../domain/models/note.dart';
import 'markdown_note_body.dart';

class NoteReaderPage extends StatefulWidget {
  const NoteReaderPage({
    required this.note,
    this.onEdit,
    this.onToggleStar,
    this.onMove,
    this.onTrashToggle,
    this.onHistory,
    this.onDeleteForever,
    this.readOnly = false,
    super.key,
  });

  final Note note;
  final Future<void> Function()? onEdit;
  final Future<void> Function()? onToggleStar;
  final Future<void> Function()? onMove;
  final Future<void> Function()? onTrashToggle;
  final Future<bool> Function()? onHistory;
  final Future<bool> Function()? onDeleteForever;
  final bool readOnly;

  @override
  State<NoteReaderPage> createState() => _NoteReaderPageState();
}

class _NoteReaderPageState extends State<NoteReaderPage> {
  WebViewController? _webView;
  bool _showSource = false;

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
          if (note.isMarkdown) ...[
            IconButton(
              tooltip: _showSource ? '查看预览' : '查看原文',
              onPressed: () => setState(() => _showSource = !_showSource),
              icon: Icon(_showSource ? Icons.visibility_outlined : Icons.code),
            ),
            IconButton(
              tooltip: '复制 Markdown 原文',
              onPressed: () => copyNoteText(context, note.content),
              icon: const Icon(Icons.copy_outlined),
            ),
          ],
          if (!widget.readOnly) ...[
            IconButton(
              tooltip: '编辑',
              onPressed: () async {
                await widget.onEdit?.call();
                if (context.mounted) Navigator.of(context).pop();
              },
              icon: const Icon(Icons.edit_outlined),
            ),
            PopupMenuButton<String>(
              onSelected: (value) async {
                switch (value) {
                  case 'deleteForever':
                    final deleted = await widget.onDeleteForever?.call();
                    if (deleted == true && context.mounted) {
                      Navigator.of(context).pop();
                    }
                    return;
                  case 'history':
                    final restored = await widget.onHistory?.call();
                    if (restored == true && context.mounted) {
                      Navigator.of(context).pop();
                    }
                    return;
                  case 'star':
                    await widget.onToggleStar?.call();
                  case 'move':
                    await widget.onMove?.call();
                  case 'trash':
                    await widget.onTrashToggle?.call();
                }
                if (context.mounted) Navigator.of(context).pop();
              },
              itemBuilder: (_) => [
                if (note.isTrash && widget.onDeleteForever != null)
                  const PopupMenuItem(
                    value: 'deleteForever',
                    child: Text('彻底删除'),
                  ),
                if (widget.onHistory != null)
                  const PopupMenuItem(value: 'history', child: Text('历史版本')),
                PopupMenuItem(
                  value: 'star',
                  child: Text(note.isStarred ? '取消星标' : '添加星标'),
                ),
                const PopupMenuItem(value: 'move', child: Text('移动到笔记本')),
                PopupMenuItem(
                  value: 'trash',
                  child: Text(note.isTrash ? '恢复笔记' : '移入回收站'),
                ),
              ],
            ),
          ],
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Metadata(note: note),
          Expanded(
            child: note.isMarkdown
                ? _showSource
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: SelectableText(
                            note.content,
                            style: const TextStyle(fontSize: 16, height: 1.65),
                          ),
                        )
                      : MarkdownNoteBody(content: note.content)
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
