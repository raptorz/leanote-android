import 'package:flutter/material.dart';

import '../services/note_link_opener.dart';

class NoteLinkDialog extends StatefulWidget {
  const NoteLinkDialog({
    super.key,
    required this.href,
    required this.onCopy,
    this.opener,
  });
  final String href;
  final Future<void> Function() onCopy;
  final NoteLinkOpener? opener;

  @override
  State<NoteLinkDialog> createState() => _NoteLinkDialogState();
}

class _NoteLinkDialogState extends State<NoteLinkDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _open() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await (widget.opener ?? NoteLinkOpener()).open(widget.href);
      if (mounted) Navigator.pop(context);
    } on Object {
      if (mounted) setState(() => _error = '无法打开链接，请重试或复制地址到浏览器');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uri = externalNoteLink(widget.href);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('链接地址'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(widget.href),
              const SizedBox(height: 12),
              if (uri != null) ...[
                Text('目标网站：${uri.host}'),
                const Text('确认后交给浏览器或系统关联应用打开。'),
              ] else
                const Text('此地址仅支持查看和复制。'),
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
          if (uri != null)
            FilledButton(
              onPressed: _busy ? null : _open,
              child: const Text('外部打开'),
            ),
          TextButton(
            onPressed: _busy ? null : widget.onCopy,
            child: const Text('复制链接'),
          ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
