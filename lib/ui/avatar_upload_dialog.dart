import 'dart:typed_data';

import 'package:flutter/material.dart';

class AvatarUploadDialog extends StatefulWidget {
  const AvatarUploadDialog({
    super.key,
    required this.identity,
    required this.bytes,
    required this.upload,
  });
  final String identity;
  final Uint8List bytes;
  final Future<void> Function(String identity, String password) upload;
  @override
  State<AvatarUploadDialog> createState() => _AvatarUploadDialogState();
}

class _AvatarUploadDialogState extends State<AvatarUploadDialog> {
  late final _identity = TextEditingController(text: widget.identity);
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _identity.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _upload() async {
    if (_busy) return;
    if (_identity.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = '请填写当前账号和密码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.upload(_identity.text.trim(), _password.text);
      _password.clear();
      if (mounted) Navigator.pop(context, true);
    } on Object {
      _password.clear();
      if (mounted) {
        setState(
          () => _error = '上传失败，请检查网络、当前账号密码或服务端上传限制。超时后请先取消并刷新头像确认结果，不要重复上传。',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('更换头像'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.memory(widget.bytes, width: 96, height: 96),
            const Text('图片已转换为小尺寸 PNG。需要当前密码验证身份；密码不会保存。'),
            TextField(
              controller: _identity,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: '当前登录账号（用户名或邮箱）'),
            ),
            TextField(
              controller: _password,
              enabled: !_busy,
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
          onPressed: _busy ? null : _upload,
          child: const Text('上传'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
      ],
    ),
  );
}
