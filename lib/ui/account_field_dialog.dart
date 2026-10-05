import 'package:flutter/material.dart';

class AccountFieldDialog extends StatefulWidget {
  const AccountFieldDialog({
    super.key,
    required this.identity,
    required this.value,
    required this.save,
    this.emailChange = false,
  });
  final String identity;
  final String value;
  final bool emailChange;
  final Future<void> Function(String identity, String password, String value)
  save;
  @override
  State<AccountFieldDialog> createState() => _AccountFieldDialogState();
}

class _AccountFieldDialogState extends State<AccountFieldDialog> {
  late final _identity = TextEditingController(text: widget.identity);
  late final _value = TextEditingController(text: widget.value);
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _identity.dispose();
    _value.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_identity.text.trim().isEmpty ||
        _password.text.isEmpty ||
        _value.text.trim().isEmpty) {
      setState(() => _error = '请填写全部字段');
      return;
    }
    if (widget.emailChange &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_value.text.trim())) {
      setState(() => _error = '请输入有效的邮箱地址');
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
        _value.text.trim(),
      );
      _password.clear();
      if (mounted) Navigator.pop(context, true);
    } on Object {
      _password.clear();
      if (mounted) {
        setState(
          () => _error = widget.emailChange
              ? '发送失败，请检查网络、当前账号密码及邮箱。若请求超时，请先检查收件箱，勿重复发送。'
              : '修改失败，请检查网络、当前账号密码或用户名是否可用。若请求超时，请先刷新资料确认结果。',
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
      title: Text(widget.emailChange ? '修改邮箱' : '修改用户名'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('需要联网验证当前账号。密码仅用于本次操作，不会保存。'),
            if (widget.emailChange) const Text('发送验证邮件后，需在新邮箱中点击链接确认，邮箱才会变更。'),
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
              controller: _value,
              enabled: !_busy,
              keyboardType: widget.emailChange
                  ? TextInputType.emailAddress
                  : TextInputType.text,
              decoration: InputDecoration(
                labelText: widget.emailChange ? '新邮箱' : '新用户名',
              ),
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
          onPressed: _busy ? null : _save,
          child: Text(widget.emailChange ? '发送验证邮件' : '保存'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
      ],
    ),
  );
}
