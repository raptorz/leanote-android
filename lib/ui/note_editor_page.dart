import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/models/note.dart';
import 'markdown_editing.dart';
import 'markdown_note_body.dart';

class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({required this.note, required this.saveText, super.key});

  final Note note;
  final Future<void> Function(String title, String content) saveText;

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

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.note.title);
    _content = TextEditingController(text: widget.note.content);
    _savedTitle = widget.note.title;
    _savedContent = widget.note.content;
    _title.addListener(_changed);
    _content.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _contentFocus.dispose();
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _flush);
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
      title: Text(widget.note.isMarkdown ? '编辑 Markdown' : '编辑笔记'),
      actions: [
        if (widget.note.isMarkdown)
          IconButton(
            tooltip: _preview ? '继续编辑' : '预览 Markdown',
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
              readOnly: _closing,
              controller: _title,
              autofocus: widget.note.title.isEmpty,
              decoration: const InputDecoration(hintText: '笔记标题'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (widget.note.isMarkdown && !_preview)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
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
                ),
              ),
            Expanded(
              child: _preview
                  ? MarkdownNoteBody(content: _content.text)
                  : TextField(
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
                            : '开始记录…',
                        border: InputBorder.none,
                      ),
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
