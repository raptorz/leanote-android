import 'package:flutter/material.dart';

class CreateTagDialog extends StatefulWidget {
  const CreateTagDialog({required this.onCreate, super.key});

  final Future<void> Function(String) onCreate;

  @override
  State<CreateTagDialog> createState() => _CreateTagDialogState();
}

class _CreateTagDialogState extends State<CreateTagDialog> {
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_busy || !_name.value.composing.isCollapsed) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请输入标签名称');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onCreate(name);
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = '未能确认创建成功：$error。若请求中断，请先同步核对标签列表。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('创建标签'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('需要联网。创建的标签可以稍后添加到笔记，不会修改已有笔记。'),
            TextField(
              controller: _name,
              enabled: !_busy,
              autofocus: true,
              maxLength: 200,
              decoration: const InputDecoration(labelText: '标签名称'),
              onSubmitted: (_) => _create(),
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
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _create,
          child: const Text('创建'),
        ),
      ],
    ),
  );
}
