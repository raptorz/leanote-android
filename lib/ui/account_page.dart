import '../l10n/app_strings.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../domain/models/account.dart';
import '../repositories/auth_repository.dart';
import 'account_avatar.dart';
import 'account_field_dialog.dart';
import 'password_change_dialog.dart';
import 'avatar_upload_dialog.dart';
import 'avatar_crop_dialog.dart';
import '../services/avatar_picker.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({
    super.key,
    required this.repository,
    required this.session,
    this.avatarPicker,
  });
  final AuthRepository repository;
  final StoredSession session;
  final AvatarPicker? avatarPicker;
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  late Account _account;
  bool _busy = true;
  String? _error;
  Uint8List? _avatar;
  bool _passwordChanged = false;

  Future<void> _uploadAvatar({bool camera = false}) async {
    if (_busy || _passwordChanged) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    bool uploaded = false;
    try {
      final picker =
          widget.avatarPicker ??
          AvatarPicker(strings: AppStrings.snapshot(context));
      final source = await (camera ? picker.capture() : picker.pick());
      if (source == null || !mounted) return;
      final bytes = await showDialog<Uint8List>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AvatarCropDialog(bytes: source),
      );
      if (bytes == null || !mounted) return;
      uploaded =
          await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => AvatarUploadDialog(
              bytes: bytes,
              upload: () =>
                  widget.repository.uploadAvatar(widget.session, bytes: bytes),
            ),
          ) ==
          true;
      if (uploaded && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(trNow(context, 'm0027'))));
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = trNow(context, 'm0028', [error]));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (uploaded && mounted) await _refresh();
  }

  Future<void> _finishPasswordChange() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // The server revoked the old token. Keep dirty notes, don't try uploading.
      await widget.repository.logout(
        widget.session,
        discardSessionWithPendingChanges: true,
      );
      if (mounted) Navigator.pop(context, true);
    } on Object {
      if (mounted) setState(() => _error = trNow(context, 'm0029'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
      if (mounted) setState(() => _error = trNow(context, 'm0030', [error]));
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
      await widget.repository.refreshAccountPresentation(widget.session);
      final profile = await widget.repository.cachedProfile(widget.session);
      if (mounted) setState(() => _account = profile);
      try {
        final avatar = await widget.repository.cachedAvatar(widget.session);
        if (mounted) setState(() => _avatar = avatar);
      } on Object catch (error) {
        if (mounted) setState(() => _error = trNow(context, 'm0031', [error]));
      }
    } catch (error) {
      if (mounted) setState(() => _error = trNow(context, 'm0032', [error]));
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
        SelectableText(value.isEmpty ? trNow(context, 'm0033') : value),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_passwordChanged,
    child: Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'm0034')),
        actions: [
          IconButton(
            tooltip: tr(context, 'm0035'),
            onPressed: _busy || _passwordChanged ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _passwordChanged
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tr(context, 'm0036')),
                  if (_error != null) Text(trMessage(context, _error!)),
                  FilledButton(
                    onPressed: _busy ? null : _finishPasswordChange,
                    child: Text(tr(context, 'm0037')),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (_busy) const LinearProgressIndicator(),
                Center(child: AccountAvatar(bytes: _avatar, size: 80)),
                OutlinedButton(
                  onPressed: _busy ? null : _uploadAvatar,
                  child: Text(tr(context, 'm0038')),
                ),
                if ((widget.avatarPicker ??
                        AvatarPicker(strings: AppStrings.snapshot(context)))
                    .cameraSupported)
                  OutlinedButton(
                    onPressed: _busy ? null : () => _uploadAvatar(camera: true),
                    child: Text(tr(context, 'm0039')),
                  ),
                if (_error != null)
                  Text(
                    trMessage(context, _error!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                _field(tr(context, 'm0040'), _account.server.toString()),
                _field(tr(context, 'm0041'), _account.username),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          final saved = await showDialog<bool>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => AccountFieldDialog(
                              value: _account.username,
                              save: (_, username) =>
                                  widget.repository.updateUsername(
                                    widget.session,
                                    username: username,
                                  ),
                            ),
                          );
                          if (saved == true && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(tr(context, 'm0042'))),
                            );
                            await _refresh();
                          }
                        },
                  child: Text(tr(context, 'm0017')),
                ),
                _field(tr(context, 'm0043'), _account.email),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          final sent = await showDialog<bool>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => AccountFieldDialog(
                              emailChange: true,
                              value: '',
                              save: (password, email) =>
                                  widget.repository.requestEmailChange(
                                    widget.session,
                                    identity: _account.email.isEmpty
                                        ? _account.username
                                        : _account.email,
                                    password: password,
                                    email: email,
                                  ),
                            ),
                          );
                          if (sent == true && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(tr(context, 'm0044'))),
                            );
                          }
                        },
                  child: Text(tr(context, 'm0016')),
                ),
                _field(tr(context, 'm0045'), _account.userId),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          final changed = await showDialog<bool>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => PasswordChangeDialog(
                              identity: _account.email.isEmpty
                                  ? _account.username
                                  : _account.email,
                              save: (identity, oldPassword, password) =>
                                  widget.repository.changePassword(
                                    widget.session,
                                    identity: identity,
                                    oldPassword: oldPassword,
                                    password: password,
                                  ),
                            ),
                          );
                          if (changed == true && mounted) {
                            setState(() => _passwordChanged = true);
                            await _finishPasswordChange();
                          }
                        },
                  child: Text(tr(context, 'm0046')),
                ),
                const Divider(),
                Text(tr(context, 'm0047')),
              ],
            ),
    ),
  );
}
