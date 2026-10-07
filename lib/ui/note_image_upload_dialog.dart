import 'package:flutter/material.dart';

import '../services/note_image_picker.dart';

class NoteImageUploadDialog extends StatefulWidget {
  const NoteImageUploadDialog({
    required this.identity,
    required this.image,
    required this.upload,
    super.key,
  });

  final String identity;
  final NoteImageUpload image;
  final Future<String> Function(String identity, String password) upload;

  @override
  State<NoteImageUploadDialog> createState() => _NoteImageUploadDialogState();
}

class _NoteImageUploadDialogState extends State<NoteImageUploadDialog> {
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
      final reference = await widget.upload(
        _identity.text.trim(),
        _password.text,
      );
      if (mounted) Navigator.of(context).pop(reference);
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = '上传未完成或结果未确认：$error。正文未插入图片；图片资源可能已经上传，请勿直接重复提交。',
        );
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
      title: const Text('插入正文图片'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.memory(widget.image.bytes, height: 140, fit: BoxFit.contain),
            const Text(
              '将先上传当前笔记，再上传图片。插入后的正文保存到本地，下次同步后图片才会关联到服务端笔记。需要当前密码验证，密码不会保存。',
            ),
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
          child: const Text('上传并插入'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(_attempted ? '关闭' : '取消'),
        ),
      ],
    ),
  );
}
