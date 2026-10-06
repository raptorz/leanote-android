import 'package:flutter/material.dart';

import 'visual_html_policy.dart';

class EditorLinkDialog extends StatefulWidget {
  const EditorLinkDialog({super.key});

  @override
  State<EditorLinkDialog> createState() => _EditorLinkDialogState();
}

class _EditorLinkDialogState extends State<EditorLinkDialog> {
  final _url = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _url.text.trim();
    if (!isSafeEditorLink(value)) {
      setState(() => _error = '请输入有效的 http:// 或 https:// 链接，不支持内嵌账号密码。');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('插入链接'),
    content: TextField(
      controller: _url,
      autofocus: true,
      keyboardType: TextInputType.url,
      autocorrect: false,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(
        labelText: '链接地址',
        hintText: 'https://',
        errorText: _error,
        errorMaxLines: 3,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('确定')),
    ],
  );
}
