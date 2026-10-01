import 'package:flutter/material.dart';

import '../domain/models/tag_choices.dart';

class NoteTagsDialog extends StatefulWidget {
  const NoteTagsDialog({
    super.key,
    required this.tags,
    required this.onSave,
    this.loadSuggestions,
  });
  final List<String> tags;
  final Future<void> Function(List<String>) onSave;
  final Future<Map<String, int>> Function()? loadSuggestions;
  @override
  State<NoteTagsDialog> createState() => _NoteTagsDialogState();
}

class _NoteTagsDialogState extends State<NoteTagsDialog> {
  late final List<String> _tags = widget.tags.toSet().toList();
  final _input = TextEditingController();
  bool _busy = false;
  String? _error;
  late Future<Map<String, int>> _suggestions;

  @override
  void initState() {
    super.initState();
    _suggestions = _loadSuggestions();
  }

  Future<Map<String, int>> _loadSuggestions() async =>
      await widget.loadSuggestions?.call() ?? <String, int>{};
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _add() {
    if (_busy || !_input.value.composing.isCollapsed) return;
    final tag = _input.text.trim();
    if (tag.isEmpty) return;
    setState(() {
      if (!_tags.contains(tag)) _tags.add(tag);
      _input.clear();
    });
  }

  Future<void> _save() async {
    if (_busy || !_input.value.composing.isCollapsed) return;
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
                onChanged: (_) => setState(() {}),
              ),
              if (widget.loadSuggestions != null)
                FutureBuilder<Map<String, int>>(
                  future: _suggestions,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _suggestions = _loadSuggestions();
                              }),
                        child: const Text('读取已有标签失败，点击重试'),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const LinearProgressIndicator();
                    }
                    final choices = tagChoices(
                      snapshot.data!,
                      query: _input.text,
                      excluded: _tags.toSet(),
                      limit: 20,
                    );
                    if (choices.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('已有标签'),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 120),
                          child: SingleChildScrollView(
                            child: Wrap(
                              spacing: 6,
                              children: [
                                for (final choice in choices)
                                  ActionChip(
                                    label: Text(choice.key),
                                    onPressed: _busy
                                        ? null
                                        : () => setState(() {
                                            _tags.add(choice.key);
                                            _input.clear();
                                          }),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
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
