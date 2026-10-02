import 'package:flutter/material.dart';

import '../domain/models/note.dart';
import '../services/note_importer.dart';

class ImportNoteDialog extends StatefulWidget {
  const ImportNoteDialog({super.key, required this.onImport, this.importer});
  final Future<Note> Function(ImportedNote) onImport;
  final NoteImporter? importer;
  @override
  State<ImportNoteDialog> createState() => _ImportNoteDialogState();
}

class _ImportNoteDialogState extends State<ImportNoteDialog> {
  ImportedNote? _note;
  bool _busy = false;
  String? _error;
  Future<void> _pick() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final note = await (widget.importer ?? NoteImporter()).pick();
      if (mounted && note != null) setState(() => _note = note);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '读取失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy || _note == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final note = await widget.onImport(_note!);
      if (mounted) Navigator.pop(context, note);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '导入失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('导入笔记原文'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '支持 UTF-8 的 Markdown、TXT、HTML，最多 32 MiB。TXT 按 Markdown 保存；不导入关联图片或附件，不执行 HTML。确认后保存到当前笔记本，待后续同步上传。',
            ),
            TextButton(
              onPressed: _busy ? null : _pick,
              child: const Text('选择文件'),
            ),
            if (_note != null) ...[
              Text(_note!.title),
              Text(
                '格式：${_note!.isMarkdown ? "Markdown" : "HTML"}，${_note!.content.length} 个字符',
              ),
            ],
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_busy) const LinearProgressIndicator(),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: _busy || _note == null ? null : _import,
          child: const Text('导入'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    ),
  );
}
