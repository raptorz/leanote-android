import 'package:flutter/material.dart';

import '../repositories/auth_repository.dart';
import '../sync/sync_coordinator.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    required this.repository,
    required this.onSignedIn,
    super.key,
  });

  final AuthRepository repository;
  final ValueChanged<StoredSession> onSignedIn;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _server = TextEditingController();
  final _identity = TextEditingController();
  final _password = TextEditingController();
  var _busy = false;
  String? _error;
  SyncProgress? _progress;

  @override
  void dispose() {
    _server.dispose();
    _identity.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate() || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = null;
    });
    try {
      final session = await widget.repository.loginAndDownload(
        serverAddress: _server.text,
        identity: _identity.text,
        password: _password.text,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      if (mounted) widget.onSignedIn(session);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Image.asset('assets/images/gemsnote_s.png', height: 72),
                        const SizedBox(height: 12),
                        Text(
                          '珠玑笔记',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const Text('日积字句，终得珠玑。', textAlign: TextAlign.center),
                        const SizedBox(height: 28),
                        TextFormField(
                          controller: _server,
                          keyboardType: TextInputType.url,
                          autofillHints: const [AutofillHints.url],
                          decoration: const InputDecoration(
                            labelText: '服务器地址',
                            hintText: 'https://notes.example.com',
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? '请输入服务器地址'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _identity,
                          autofillHints: const [AutofillHints.username],
                          decoration: const InputDecoration(
                            labelText: '邮箱或用户名',
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? '请输入邮箱或用户名'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          obscureText: true,
                          autofillHints: const [AutofillHints.password],
                          decoration: const InputDecoration(labelText: '密码'),
                          validator: (value) =>
                              value == null || value.isEmpty ? '请输入密码' : null,
                          onFieldSubmitted: (_) => _login(),
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        if (_busy)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Column(
                              children: [
                                const LinearProgressIndicator(),
                                const SizedBox(height: 8),
                                Text(_progressText(_progress)),
                              ],
                            ),
                          ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _busy ? null : _login,
                          child: const Text('登录'),
                        ),
                        TextButton(onPressed: null, child: const Text('找回密码')),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _progressText(SyncProgress? progress) {
    if (progress == null) return '正在登录…';
    final label = switch (progress.stage) {
      SyncStage.uploading => '正在上传本地修改',
      SyncStage.notebooks => '正在同步笔记本',
      SyncStage.notes => '正在同步笔记',
      SyncStage.tags => '正在同步标签',
      SyncStage.saving => '正在保存离线数据',
    };
    return '$label · ${progress.completed}';
  }

  static String _message(Object error) {
    final code = error.toString();
    return switch (code) {
      'networkUnavailable' => '无法连接服务器，请检查地址和网络。',
      'serverMigrationRequired' => '该地址不是 Gemsnote API2 服务端。',
      'clientUpgradeRequired' => '客户端版本过低，请先升级。',
      'serverUpgradeRequired' => '服务端版本过低，请先升级。',
      'invalidServerAddress' ||
      'FormatException: invalidServerAddress' => '服务器地址无效。',
      _ => '登录或同步失败：$code',
    };
  }
}
