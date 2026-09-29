import 'package:flutter/material.dart';

class NoteTagsDialog extends StatefulWidget {
  const NoteTagsDialog({super.key, required this.tags, required this.onSave});
  final List<String> tags;
  final Future<void> Function(List<String>) onSave;
  @override
  State<NoteTagsDialog> createState() => _NoteTagsDialogState();
}

class _NoteTagsDialogState extends State<NoteTagsDialog> {
  late final List<String> _tags = widget.tags.toSet().toList();
  final _input = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _add() {
    final tag = _input.text.trim();
    if (tag.isEmpty) return;
    setState(() {
      if (!_tags.contains(tag)) _tags.add(tag);
      _input.clear();
    });
  }

  Future<void> _save() async {
    if (_busy) return;
    _add();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(List.unmodifiable(_tags));
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '保存失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('编辑标签'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('每次输入一个标签。保存到本地后，需要同步才会更新服务端。'),
              const Text('受当前接口限制，已有标签不能全部清空。'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                children: [
                  for (final tag in _tags)
                    InputChip(
                      label: Text(tag),
                      onDeleted: _busy
                          ? null
                          : () => setState(() => _tags.remove(tag)),
                    ),
                ],
              ),
              TextField(
                controller: _input,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: '新标签',
                  suffixIcon: IconButton(
                    tooltip: '添加标签',
                    onPressed: _busy ? null : _add,
                    icon: const Icon(Icons.add),
                  ),
                ),
                onSubmitted: (_) => _add(),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('保存')),
      ],
    ),
  );
}
