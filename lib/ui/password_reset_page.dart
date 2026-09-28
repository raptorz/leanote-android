import 'package:flutter/material.dart';

import '../repositories/auth_repository.dart';

class PasswordResetPage extends StatefulWidget {
  const PasswordResetPage({
    super.key,
    required this.repository,
    this.serverAddress = '',
    this.email = '',
  });
  final AuthRepository repository;
  final String serverAddress;
  final String email;
  @override
  State<PasswordResetPage> createState() => _PasswordResetPageState();
}

class _PasswordResetPageState extends State<PasswordResetPage> {
  final _form = GlobalKey<FormState>();
  late final _server = TextEditingController(text: widget.serverAddress);
  late final _email = TextEditingController(text: widget.email);
  bool _busy = false;
  bool _sent = false;
  String? _error;
  @override
  void dispose() {
    _server.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.requestPasswordReset(_server.text, _email.text);
      if (mounted) setState(() => _sent = true);
    } catch (error) {
      if (mounted) setState(() => _error = '请求失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('找回密码')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: _sent
          ? const Text('请求已提交，请检查邮箱并按邮件说明重置密码。完成后返回登录页面。')
          : Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _server,
                    enabled: !_busy,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(labelText: '服务器地址'),
                    validator: (value) {
                      try {
                        AuthRepository.normalizeServer(value ?? '');
                        return null;
                      } catch (_) {
                        return '请输入有效的服务器地址';
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _email,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: '账号邮箱'),
                    validator: (value) =>
                        RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                            .hasMatch(value?.trim() ?? '')
                        ? null
                        : '请输入有效的邮箱地址',
                  ),
                  const SizedBox(height: 16),
                  const Text('需要服务器已配置邮件发送功能。如果无法收到邮件，请联系管理员重置密码。'),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  if (_busy) const LinearProgressIndicator(),
                  FilledButton(
                    onPressed: _busy ? null : _send,
                    child: const Text('发送重置邮件'),
                  ),
                ],
              ),
            ),
    ),
  );
}
