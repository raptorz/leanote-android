import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../domain/models/note.dart';
import 'markdown_note_body.dart';
import 'safe_html_note_body.dart';
import 'cached_markdown_image.dart';

class NoteReaderPage extends StatefulWidget {
  const NoteReaderPage({
    required this.note,
    this.onEdit,
    this.onToggleStar,
    this.onMove,
    this.onCopy,
    this.onTrashToggle,
    this.onHistory,
    this.onDeleteForever,
    this.onEditTags,
    this.onFiles,
    this.onExport,
    this.onSystemShare,
    this.loadCachedImage,
    this.downloadImage,
    this.canDownloadImage,
    this.readOnly = false,
    this.safeHtmlPreview = true,
    super.key,
  });

  final Note note;
  final Future<void> Function()? onEdit;
  final Future<void> Function()? onToggleStar;
  final Future<void> Function()? onMove;
  final Future<bool> Function()? onCopy;
  final Future<void> Function()? onTrashToggle;
  final Future<bool> Function()? onHistory;
  final Future<bool> Function()? onDeleteForever;
  final Future<bool> Function()? onEditTags;
  final Future<void> Function()? onFiles;
  final Future<bool> Function()? onExport;
  final Future<void> Function(Rect origin)? onSystemShare;
  final CachedImageLoader? loadCachedImage;
  final Future<Uint8List> Function(Uri)? downloadImage;
  final bool Function(Uri)? canDownloadImage;
  final bool readOnly;
  final bool safeHtmlPreview;

  @override
  State<NoteReaderPage> createState() => _NoteReaderPageState();
}

class _NoteReaderPageState extends State<NoteReaderPage> {
  WebViewController? _webView;
  bool _showSource = false;
  int _imageRevision = 0;
  bool _exporting = false;
  bool _sharing = false;
  bool _copying = false;
  final _menuKey = GlobalKey();

  Future<void> _share() async {
    if (_sharing || widget.onSystemShare == null) return;
    setState(() => _sharing = true);
    try {
      final box = _menuKey.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) throw StateError('分享位置不可用');
      await widget.onSystemShare!(box.localToGlobal(Offset.zero) & box.size);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('系统分享失败，请重试；较大笔记请使用导出原文（分享最多 256 KiB）')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _export() async {
    if (_exporting || widget.onExport == null) return;
    setState(() => _exporting = true);
    try {
      final saved = await widget.onExport!();
      if (mounted && saved) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('笔记已导出')));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('导出失败，请检查保存位置或可用空间后重试')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    if (!widget.note.isMarkdown && !widget.safeHtmlPreview) {
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
          if (note.isMarkdown || widget.safeHtmlPreview) ...[
            IconButton(
              tooltip: _showSource ? '查看预览' : '查看原文',
              onPressed: () => setState(() => _showSource = !_showSource),
              icon: Icon(_showSource ? Icons.visibility_outlined : Icons.code),
            ),
            IconButton(
              tooltip: note.isMarkdown ? '复制 Markdown 原文' : '复制 HTML 原文',
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
              key: _menuKey,
              onSelected: (value) async {
                switch (value) {
                  case 'copy':
                    if (_copying) return;
                    setState(() => _copying = true);
                    try {
                      final copied = await widget.onCopy?.call();
                      if (copied == true && context.mounted) {
                        Navigator.of(context).pop();
                      }
                    } finally {
                      if (mounted) setState(() => _copying = false);
                    }
                    return;
                  case 'systemShare':
                    await _share();
                    return;
                  case 'export':
                    await _export();
                    return;
                  case 'files':
                    await widget.onFiles?.call();
                    if (mounted) setState(() => _imageRevision++);
                    return;
                  case 'tags':
                    final saved = await widget.onEditTags?.call();
                    if (saved == true && context.mounted) {
                      Navigator.of(context).pop();
                    }
                    return;
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
                if (widget.onSystemShare != null)
                  PopupMenuItem(
                    value: 'systemShare',
                    enabled: !_sharing,
                    child: Text(_sharing ? '正在分享…' : '系统分享原文'),
                  ),
                if (widget.onExport != null)
                  PopupMenuItem(
                    value: 'export',
                    enabled: !_exporting,
                    child: Text(_exporting ? '正在导出…' : '导出原文'),
                  ),
                if (widget.onFiles != null)
                  const PopupMenuItem(value: 'files', child: Text('图片与附件')),
                if (widget.onEditTags != null)
                  const PopupMenuItem(value: 'tags', child: Text('编辑标签')),
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
                if (!note.isTrash && widget.onCopy != null)
                  PopupMenuItem(
                    value: 'copy',
                    enabled: !_copying,
                    child: Text(_copying ? '正在复制…' : '复制到笔记本'),
                  ),
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
                      : MarkdownNoteBody(
                          key: ValueKey(_imageRevision),
                          content: note.content,
                          loadCachedImage: widget.loadCachedImage,
                          downloadImage: widget.downloadImage,
                          canDownloadImage: widget.canDownloadImage,
                        )
                : widget.safeHtmlPreview
                ? _showSource
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: SelectableText(note.content),
                        )
                      : SafeHtmlNoteBody(
                          key: ValueKey(_imageRevision),
                          content: note.content,
                          loadCachedImage: widget.loadCachedImage,
                          downloadImage: widget.downloadImage,
                          canDownloadImage: widget.canDownloadImage,
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
