import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/models/note.dart';

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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.note.isMarkdown ? '编辑 Markdown' : '编辑笔记'),
      actions: [
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
            Expanded(
              child: TextField(
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
