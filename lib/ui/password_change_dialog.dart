import 'package:flutter/material.dart';

class PasswordChangeDialog extends StatefulWidget {
  const PasswordChangeDialog({
    super.key,
    required this.identity,
    required this.save,
  });
  final String identity;
  final Future<void> Function(
    String identity,
    String oldPassword,
    String password,
  )
  save;
  @override
  State<PasswordChangeDialog> createState() => _PasswordChangeDialogState();
}

class _PasswordChangeDialogState extends State<PasswordChangeDialog> {
  late final _identity = TextEditingController(text: widget.identity);
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;
  void _clearPasswords() {
    _old.clear();
    _new.clear();
    _confirm.clear();
  }

  @override
  void dispose() {
    _identity.dispose();
    _old.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_identity.text.trim().isEmpty ||
        _old.text.isEmpty ||
        _new.text.isEmpty) {
      setState(() => _error = '请填写全部字段');
      return;
    }
    if (_new.text != _confirm.text) {
      setState(() => _error = '两次输入的新密码不一致');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.save(_identity.text.trim(), _old.text, _new.text);
      _clearPasswords();
      if (mounted) Navigator.pop(context, true);
    } on Object {
      _clearPasswords();
      if (mounted) {
        setState(
          () => _error =
              '修改失败，请检查网络、当前密码和新密码要求。若请求超时，密码可能已修改，请取消并用新密码重新登录确认，勿自动重试。',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _password(TextEditingController controller, String label) => TextField(
    controller: controller,
    enabled: !_busy,
    obscureText: true,
    autocorrect: false,
    enableSuggestions: false,
    decoration: InputDecoration(labelText: label),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('修改密码'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '修改成功会使所有设备的登录状态失效，并返回登录页。本地笔记和未上传修改会保留；重新登录同一账号时请选择保留缓存，不要重新同步。',
            ),
            TextField(
              controller: _identity,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: '当前登录账号（用户名或邮箱）'),
            ),
            _password(_old, '当前密码'),
            _password(_new, '新密码'),
            _password(_confirm, '确认新密码'),
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
          onPressed: _busy ? null : _save,
          child: const Text('修改并退出登录'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
      ],
    ),
  );
}
