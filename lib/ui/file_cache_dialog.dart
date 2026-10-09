import 'package:flutter/material.dart';

import '../domain/models/file_cache_usage.dart';

class FileCacheDialog extends StatefulWidget {
  const FileCacheDialog({
    super.key,
    required this.accountLabel,
    required this.load,
    required this.clear,
  });
  final String accountLabel;
  final Future<FileCacheUsage> Function() load;
  final Future<void> Function() clear;

  @override
  State<FileCacheDialog> createState() => _FileCacheDialogState();
}

class _FileCacheDialogState extends State<FileCacheDialog> {
  FileCacheUsage? _usage;
  bool _busy = true;
  bool _confirming = false;
  bool _cleared = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final usage = await widget.load();
      if (mounted) setState(() => _usage = usage);
    } on Object {
      if (mounted) setState(() => _error = '读取缓存用量失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    if (_busy || !_confirming) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.clear();
      if (mounted) {
        setState(() {
          _usage = const FileCacheUsage(files: 0, bytes: 0);
          _cleared = true;
          _confirming = false;
        });
      }
    } on Object {
      if (mounted) setState(() => _error = '清理缓存失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('离线资源缓存'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.accountLabel),
            const SizedBox(height: 12),
            if (_usage != null)
              Text('${_usage!.files} 个文件 · ${_usage!.sizeLabel}'),
            const Text('仅统计当前账号已下载的图片和附件。清理后需联网重新下载；笔记正文、待同步修改和文件列表会保留。'),
            const SizedBox(height: 8),
            const Text('不包含导出或分享产生的副本。数据库空间可供后续复用，应用占用空间不一定立即缩小。'),
            if (_confirming) const Text('确认清理当前账号的离线图片和附件？'),
            if (_cleared) const Text('离线资源缓存已清理'),
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
        if (_usage == null && !_busy)
          TextButton(onPressed: _load, child: const Text('重试读取')),
        if (_usage != null && _usage!.files > 0)
          FilledButton(
            onPressed: _busy
                ? null
                : _confirming
                ? _clear
                : () => setState(() => _confirming = true),
            child: Text(_confirming ? '确认清理' : '清理缓存'),
          ),
        TextButton(
          onPressed: _busy
              ? null
              : () {
                  if (_confirming) {
                    setState(() {
                      _confirming = false;
                      _error = null;
                    });
                  } else {
                    Navigator.pop(context);
                  }
                },
          child: Text(_confirming ? '取消' : '关闭'),
        ),
      ],
    ),
  );
}
