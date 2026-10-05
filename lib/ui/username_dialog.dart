import 'package:flutter/material.dart';

class UsernameDialog extends StatefulWidget {
  const UsernameDialog({
    super.key,
    required this.identity,
    required this.username,
    required this.save,
  });
  final String identity;
  final String username;
  final Future<void> Function(String identity, String password, String username)
  save;
  @override
  State<UsernameDialog> createState() => _UsernameDialogState();
}

class _UsernameDialogState extends State<UsernameDialog> {
  late final _identity = TextEditingController(text: widget.identity);
  late final _username = TextEditingController(text: widget.username);
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _identity.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_identity.text.trim().isEmpty ||
        _password.text.isEmpty ||
        _username.text.trim().isEmpty) {
      setState(() => _error = '请填写全部字段');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.save(
        _identity.text.trim(),
        _password.text,
        _username.text.trim(),
      );
      _password.clear();
      if (mounted) Navigator.pop(context, true);
    } on Object {
      _password.clear();
      if (mounted) {
        setState(() => _error = '修改失败，请检查网络、当前账号密码或用户名是否可用。若请求超时，请先刷新资料确认结果。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('修改用户名'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('需要联网验证当前账号。密码仅用于本次操作，不会保存。'),
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
            TextField(
              controller: _username,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: '新用户名'),
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
        FilledButton(onPressed: _busy ? null : _save, child: const Text('保存')),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
      ],
    ),
  );
}
