import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/models/note.dart';
import 'cached_markdown_image.dart';
import 'markdown_editing.dart';
import 'markdown_note_body.dart';
import 'safe_html_note_body.dart';
import 'visual_html_editor.dart';

class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({
    required this.note,
    required this.saveText,
    this.loadCachedImage,
    super.key,
  });

  final Note note;
  final Future<void> Function(String title, String content) saveText;
  // Preview is cache-only: editing arbitrary image URLs must never fetch them.
  final CachedImageLoader? loadCachedImage;

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage>
    with WidgetsBindingObserver {
  late final TextEditingController _title;
  late final TextEditingController _content;
  var _allowPop = false;
  var _closing = false;
  Timer? _debounce;
  Future<bool>? _saving;
  late String _savedTitle;
  late String _savedContent;
  String? _error;
  bool _preview = false;
  final _contentFocus = FocusNode();
  final _titleFocus = FocusNode();
  final _titleUndo = UndoHistoryController();
  final _contentUndo = UndoHistoryController();
  bool _editingTitle = false;

  @override
  void initState() {
    super.initState();
    // A valid initial selection lets Flutter record the original text before
    // the first edit (including a toolbar edit made before the field is focused).
    _title = TextEditingController.fromValue(
      TextEditingValue(
        text: widget.note.title,
        selection: TextSelection.collapsed(offset: widget.note.title.length),
      ),
    );
    _content = TextEditingController.fromValue(
      TextEditingValue(
        text: widget.note.content,
        selection: TextSelection.collapsed(offset: widget.note.content.length),
      ),
    );
    _savedTitle = widget.note.title;
    _savedContent = widget.note.content;
    _title.addListener(_changed);
    _content.addListener(_changed);
    _titleFocus.addListener(_trackFocus);
    _contentFocus.addListener(_trackFocus);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _contentFocus.dispose();
    _titleFocus.dispose();
    _titleUndo.dispose();
    _contentUndo.dispose();
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _flush);
  }

  void _trackFocus() {
    if (_titleFocus.hasFocus || _contentFocus.hasFocus) {
      setState(() => _editingTitle = _titleFocus.hasFocus);
    }
  }

  Widget _historyButtons() {
    final history = _editingTitle ? _titleUndo : _contentUndo;
    return ValueListenableBuilder<UndoHistoryValue>(
      valueListenable: history,
      builder: (_, value, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '撤销',
            onPressed: !_closing && value.canUndo ? history.undo : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: '重做',
            onPressed: !_closing && value.canRedo ? history.redo : null,
            icon: const Icon(Icons.redo),
          ),
        ],
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _flush();
  }

  Future<bool> _flush() {
    _debounce?.cancel();
    return _saving ??= _drain().whenComplete(() => _saving = null);
  }

  Future<bool> _drain() async {
    while (mounted) {
      final title = _title.text;
      final content = _content.text;
      if (title == _savedTitle && content == _savedContent) return true;
      try {
        await widget.saveText(title, content);
        _savedTitle = title;
        _savedContent = content;
        if (mounted) setState(() => _error = null);
      } on Object catch (error) {
        if (mounted) setState(() => _error = '保存到本地失败：$error');
        return false;
      }
    }
    return false;
  }

  Future<void> _save() async {
    if (_allowPop || _closing) return;
    setState(() => _closing = true);
    final saved = await _flush();
    if (!mounted) return;
    if (!saved) {
      setState(() => _closing = false);
      return;
    }
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _togglePreview() {
    if (_closing) return;
    FocusScope.of(context).unfocus();
    setState(() => _preview = !_preview);
    _flush();
  }

  Widget _formatButton(
    String label,
    IconData icon,
    TextEditingValue Function(TextEditingValue) transform,
  ) => IconButton(
    tooltip: label,
    icon: Icon(icon),
    onPressed: _closing
        ? null
        : () {
            _content.value = transform(_content.value);
            _contentFocus.requestFocus();
          },
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.note.isMarkdown ? '编辑 Markdown' : '编辑 HTML 原文'),
      actions: [
        if (!widget.note.isMarkdown)
          IconButton(
            tooltip: '可视化编辑',
            icon: const Icon(Icons.format_shapes),
            onPressed: _closing
                ? null
                : () async {
                    if (!supportsVisualHtml(_content.text)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('此笔记包含图片、链接或复杂 HTML，请继续编辑原文，避免丢失内容。'),
                        ),
                      );
                      return;
                    }
                    _contentFocus.unfocus();
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => VisualHtmlEditor(
                          source: _content.text,
                          onChanged: (value) {
                            _content.text = value;
                          },
                        ),
                      ),
                    );
                    if (mounted) await _flush();
                  },
          ),
        IconButton(
          tooltip: _preview
              ? '继续编辑'
              : widget.note.isMarkdown
              ? '预览 Markdown'
              : '预览富文本',
          onPressed: _closing ? null : _togglePreview,
          icon: Icon(
            _preview ? Icons.edit_outlined : Icons.visibility_outlined,
          ),
        ),
        IconButton(
          tooltip: '保存到本地',
          onPressed: _closing ? null : _save,
          icon: const Icon(Icons.check),
        ),
      ],
    ),
    body: PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _save();
      },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_error != null)
              MaterialBanner(
                content: Text(_error!),
                actions: [
                  TextButton(onPressed: _flush, child: const Text('重试')),
                ],
              ),
            TextField(
              focusNode: _titleFocus,
              undoController: _titleUndo,
              readOnly: _closing,
              controller: _title,
              autofocus: widget.note.title.isEmpty,
              decoration: const InputDecoration(hintText: '笔记标题'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (!widget.note.isMarkdown)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('编辑 HTML 原文，预览显示基本排版及已缓存图片，不联网加载资源或执行脚本。原文将完整保存。'),
              ),
            if (!_preview)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _historyButtons(),
                    if (widget.note.isMarkdown) ...[
                      _formatButton(
                        '加粗',
                        Icons.format_bold,
                        (value) => wrapMarkdown(value, '**'),
                      ),
                      _formatButton(
                        '斜体',
                        Icons.format_italic,
                        (value) => wrapMarkdown(value, '*'),
                      ),
                      _formatButton(
                        '行内代码',
                        Icons.code,
                        (value) => wrapMarkdown(value, '`'),
                      ),
                      _formatButton(
                        '标题',
                        Icons.title,
                        (value) => prefixMarkdownLines(value, '# '),
                      ),
                      _formatButton(
                        '无序列表',
                        Icons.format_list_bulleted,
                        (value) => prefixMarkdownLines(value, '- '),
                      ),
                    ],
                  ],
                ),
              ),
            Expanded(
              child: IndexedStack(
                index: _preview ? 1 : 0,
                sizing: StackFit.expand,
                children: [
                  TextField(
                    undoController: _contentUndo,
                    focusNode: _contentFocus,
                    readOnly: _closing,
                    controller: _content,
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      hintText: widget.note.isMarkdown
                          ? '使用 Markdown 开始记录…'
                          : '输入 HTML 原文，例如 <p>开始记录…</p>',
                      border: InputBorder.none,
                    ),
                  ),
                  if (_preview)
                    widget.note.isMarkdown
                        ? MarkdownNoteBody(
                            content: _content.text,
                            loadCachedImage: widget.loadCachedImage,
                          )
                        : SafeHtmlNoteBody(
                            content: _content.text,
                            loadCachedImage: widget.loadCachedImage,
                          )
                  else
                    const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
