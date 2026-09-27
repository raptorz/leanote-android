import 'package:flutter/material.dart';

import '../domain/models/note.dart';

class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({required this.note, super.key});

  final Note note;

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late final TextEditingController _title;
  late final TextEditingController _content;
  var _allowPop = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.note.title);
    _content = TextEditingController(text: widget.note.content);
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  void _save() {
    if (_allowPop) return;
    final changed = widget.note.copyWith(
      title: _title.text.trim(),
      content: _content.text,
      updatedTime: DateTime.now().toUtc().toIso8601String(),
    );
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(changed);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.note.isMarkdown ? '编辑 Markdown' : '编辑笔记'),
      actions: [
        IconButton(
          tooltip: '保存到本地',
          onPressed: _save,
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
            TextField(
              controller: _title,
              autofocus: widget.note.title.isEmpty,
              decoration: const InputDecoration(hintText: '笔记标题'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
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
