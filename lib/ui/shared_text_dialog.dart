import 'package:flutter/material.dart';

import '../domain/models/note.dart';
import '../domain/models/notebook.dart';
import '../services/shared_text_inbox.dart';
import 'notebook_target_picker.dart';

class SharedTextDialog extends StatefulWidget {
  const SharedTextDialog({
    super.key,
    required this.source,
    required this.notebooks,
    required this.accountLabel,
    required this.canImport,
    required this.onImport,
    required this.onAcknowledge,
  });
  final SharedText source;
  final List<Notebook> notebooks;
  final String accountLabel;
  final bool canImport;
  final Future<Note> Function(SharedText source, String notebookId) onImport;
  final Future<void> Function() onAcknowledge;

  @override
  State<SharedTextDialog> createState() => _SharedTextDialogState();
}

class _SharedTextDialogState extends State<SharedTextDialog> {
  late final _title = TextEditingController(text: widget.source.suggestedTitle);
  late final _body = TextEditingController(text: widget.source.text);
  String? _notebook;
  bool _busy = false;
  Note? _imported;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    if (_busy || !widget.canImport || _notebook == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _imported ??= await widget.onImport(
        SharedText(
          id: widget.source.id,
          title: _title.text,
          text: _body.text,
          accountKey: widget.source.accountKey,
        ),
        _notebook!,
      );
      await widget.onAcknowledge();
      if (mounted) Navigator.pop(context, _imported);
    } on Object catch (failure) {
      if (mounted) {
        setState(
          () => _error = _imported == null
              ? '导入失败：$failure'
              : '笔记已保存，清理待处理分享失败：$failure。重试不会重复创建笔记。',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discard() async {
    if (_busy || _imported != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('忽略这条分享？'),
        content: const Text('将移除待处理内容，不创建笔记。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('忽略'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onAcknowledge();
      if (mounted) Navigator.pop(context);
    } on Object catch (failure) {
      if (mounted) setState(() => _error = '忽略失败：$failure');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('导入分享文本'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('保存到：${widget.accountLabel}'),
              const Text('按 Markdown 保存文本，不抓取网页或下载资源。保存后待同步上传。'),
              if (!widget.canImport) const Text('此分享已指定其他账号，请切换账号后继续，或忽略这条分享。'),
              TextField(
                controller: _title,
                enabled: !_busy && _imported == null && widget.canImport,
                decoration: const InputDecoration(labelText: '笔记标题'),
                maxLength: 200,
              ),
              TextField(
                controller: _body,
                enabled: !_busy && _imported == null && widget.canImport,
                decoration: const InputDecoration(labelText: '分享正文'),
                minLines: 2,
                maxLines: 5,
              ),
              if (widget.notebooks.isEmpty)
                const Text('请先创建笔记本，再回来导入；稍后处理会保留分享。'),
              SizedBox(
                height: 210,
                child: NotebookTargetPicker(
                  notebooks: widget.notebooks,
                  selected: _notebook,
                  enabled: !_busy && _imported == null && widget.canImport,
                  onSelected: (id) => setState(() => _notebook = id),
                ),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy || _imported != null ? null : _discard,
          child: const Text('忽略'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, _imported),
          child: const Text('稍后处理'),
        ),
        FilledButton(
          onPressed: _busy || _notebook == null || !widget.canImport
              ? null
              : _import,
          child: Text(_imported == null ? '保存笔记' : '重试清理'),
        ),
      ],
    ),
  );
}
