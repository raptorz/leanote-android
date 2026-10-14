import '../l10n/app_strings.dart';

import 'package:flutter/material.dart';

import '../services/note_image_picker.dart';

class NoteImageUploadDialog extends StatefulWidget {
  const NoteImageUploadDialog({
    required this.identity,
    required this.image,
    required this.upload,
    super.key,
  });

  final String identity;
  final NoteImageUpload image;
  final Future<String> Function(String identity, String password) upload;

  @override
  State<NoteImageUploadDialog> createState() => _NoteImageUploadDialogState();
}

class _NoteImageUploadDialogState extends State<NoteImageUploadDialog> {
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
      final reference = await widget.upload(
        _identity.text.trim(),
        _password.text,
      );
      if (mounted) Navigator.of(context).pop(reference);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = trNow(context, 'm0261', [error]));
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
      title: Text(tr(context, 'm0262')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.memory(widget.image.bytes, height: 140, fit: BoxFit.contain),
            Text(tr(context, 'm0263')),
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
          child: Text(tr(context, 'm0264')),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(_attempted ? tr(context, 'm0010') : tr(context, 'm0026')),
        ),
      ],
    ),
  );
}
