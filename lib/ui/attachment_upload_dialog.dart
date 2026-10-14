import '../l10n/app_strings.dart';

import 'package:flutter/material.dart';

import '../domain/models/attachment_upload.dart';

class AttachmentUploadDialog extends StatefulWidget {
  const AttachmentUploadDialog({
    required this.identity,
    required this.file,
    required this.upload,
    super.key,
  });
  final String identity;
  final AttachmentUpload file;
  final Future<bool> Function(String identity, String password) upload;
  @override
  State<AttachmentUploadDialog> createState() => _AttachmentUploadDialogState();
}

class _AttachmentUploadDialogState extends State<AttachmentUploadDialog> {
  late final _identity = TextEditingController(text: widget.identity);
  final _password = TextEditingController();
  bool _busy = false;
  bool _attempted = false;
  String? _error;
  @override
  void dispose() {
    _identity.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _upload() async {
    if (_busy || _attempted) return;
    if (_identity.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = trNow(context, 'm0076'));
      return;
    }
    setState(() {
      _busy = true;
      _attempted = true;
      _error = null;
    });
    try {
      final refreshed = await widget.upload(
        _identity.text.trim(),
        _password.text,
      );
      if (mounted) Navigator.of(context).pop(refreshed);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = trNow(context, 'm0077', [error]));
      }
    } finally {
      _password.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(tr(context, 'm0070')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr(context, 'm0078', [
                widget.file.name,
                widget.file.bytes.length,
              ]),
            ),
            Text(tr(context, 'm0079')),
            TextField(
              controller: _identity,
              enabled: !_busy && !_attempted,
              decoration: InputDecoration(labelText: tr(context, 'm0080')),
            ),
            TextField(
              controller: _password,
              enabled: !_busy && !_attempted,
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
          onPressed: _busy || _attempted ? null : _upload,
          child: Text(tr(context, 'm0081')),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(tr(context, 'm0026')),
        ),
      ],
    ),
  );
}
