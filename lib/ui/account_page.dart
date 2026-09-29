import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../domain/models/account.dart';
import '../repositories/auth_repository.dart';
import 'account_avatar.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({
    super.key,
    required this.repository,
    required this.session,
  });
  final AuthRepository repository;
  final StoredSession session;
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  late Account _account;
  bool _busy = true;
  String? _error;
  Uint8List? _avatar;

  @override
  void initState() {
    super.initState();
    _account = widget.session.account;
    _loadCache();
  }

  Future<void> _loadCache() async {
    try {
      final profile = await widget.repository.cachedProfile(widget.session);
      final avatar = await widget.repository.cachedAvatar(widget.session);
      if (mounted) {
        setState(() {
          _account = profile;
          _avatar = avatar;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '读取本地账号信息失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final profile = await widget.repository.refreshProfile(widget.session);
      if (mounted) setState(() => _account = profile);
      try {
        final avatar = await widget.repository.refreshAvatar(
          widget.session,
          profile,
        );
        if (mounted) setState(() => _avatar = avatar);
      } on Object catch (error) {
        if (mounted) setState(() => _error = '资料已刷新，但头像刷新失败，保留原头像：$error');
      }
    } catch (error) {
      if (mounted) setState(() => _error = '刷新失败，仍显示本地资料：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(String title, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        SelectableText(value.isEmpty ? '未设置' : value),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('账号'),
      actions: [
        IconButton(
          tooltip: '刷新资料',
          onPressed: _busy ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (_busy) const LinearProgressIndicator(),
        Center(child: AccountAvatar(bytes: _avatar, size: 80)),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        _field('服务器地址', _account.server.toString()),
        _field('用户名', _account.username),
        _field('邮箱', _account.email),
        _field('用户 ID', _account.userId),
        const Divider(),
        const Text('账号信息保存在本地，离线时也可查看。点击右上角刷新可获取服务器上的最新资料。'),
      ],
    ),
  );
}
