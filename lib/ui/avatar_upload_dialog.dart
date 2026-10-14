import '../l10n/app_strings.dart';

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
      setState(() => _error = trNow(context, 'm0088'));
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
        setState(() => _error = trNow(context, 'm0089'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(tr(context, 'm0038')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.memory(widget.bytes, width: 96, height: 96),
            Text(tr(context, 'm0090')),
            TextField(
              controller: _identity,
              enabled: !_busy,
              decoration: InputDecoration(labelText: tr(context, 'm0020')),
            ),
            TextField(
              controller: _password,
              enabled: !_busy,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(labelText: tr(context, 'm0021')),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Text(
                trMessage(context, _error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: _busy ? null : _upload,
          child: Text(tr(context, 'm0081')),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text(tr(context, 'm0026')),
        ),
      ],
    ),
  );
}
