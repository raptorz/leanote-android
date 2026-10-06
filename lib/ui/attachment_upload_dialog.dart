import 'package:flutter/material.dart';

import '../domain/models/attachment_upload.dart';

class AttachmentUploadDialog extends StatefulWidget {
  const AttachmentUploadDialog({
    required this.identity,
    required this.file,
    required this.upload,
    super.key,
  });
  final String identity;
  final AttachmentUpload file;
  final Future<bool> Function(String identity, String password) upload;
  @override
  State<AttachmentUploadDialog> createState() => _AttachmentUploadDialogState();
}

class _AttachmentUploadDialogState extends State<AttachmentUploadDialog> {
  late final _identity = TextEditingController(text: widget.identity);
  final _password = TextEditingController();
  bool _busy = false;
  bool _attempted = false;
  String? _error;
  @override
  void dispose() {
    _identity.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _upload() async {
    if (_busy || _attempted) return;
    if (_identity.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = '请输入当前账号和密码');
      return;
    }
    setState(() {
      _busy = true;
      _attempted = true;
      _error = null;
    });
    try {
      final refreshed = await widget.upload(
        _identity.text.trim(),
        _password.text,
      );
      if (mounted) Navigator.of(context).pop(refreshed);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = '上传未完成或结果未确认：$error。请关闭窗口并刷新文件列表核实，不要重复上传。');
      }
    } finally {
      _password.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('上传附件'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${widget.file.name}（${widget.file.bytes.length} 字节）'),
            const Text('将先上传当前笔记的未同步正文，再上传附件；不会同步其他笔记。需要当前密码验证，密码不会保存。'),
            TextField(
              controller: _identity,
              enabled: !_busy && !_attempted,
              decoration: const InputDecoration(labelText: '当前账号'),
            ),
            TextField(
              controller: _password,
              enabled: !_busy && !_attempted,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: '当前密码'),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: _busy || _attempted ? null : _upload,
          child: const Text('上传'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    ),
  );
}
