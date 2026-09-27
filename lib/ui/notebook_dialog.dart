import 'package:flutter/material.dart';

import '../domain/models/notebook.dart';
import '../repositories/auth_repository.dart';

class NotebookDialog extends StatefulWidget {
  const NotebookDialog({
    super.key,
    required this.repository,
    required this.session,
    this.existing,
    this.parentNotebookId = '',
  });

  final AuthRepository repository;
  final StoredSession session;
  final Notebook? existing;
  final String parentNotebookId;

  @override
  State<NotebookDialog> createState() => _NotebookDialogState();
}

class _NotebookDialogState extends State<NotebookDialog> {
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_title.text.trim().isEmpty) {
      setState(() => _error = '请输入笔记本名称');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.saveNotebook(
        widget.session,
        title: _title.text,
        existing: widget.existing,
        parentNotebookId: widget.parentNotebookId,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '保存失败：$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(
        widget.existing != null
            ? '重命名笔记本'
            : widget.parentNotebookId.isEmpty
            ? '新建笔记本'
            : '新增子笔记本',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            enabled: !_busy,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(labelText: '笔记本名称', errorText: _error),
          ),
          const SizedBox(height: 12),
          const Text('此操作需要连接服务器。'),
          if (_busy) const LinearProgressIndicator(),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('保存')),
      ],
    ),
  );
}
