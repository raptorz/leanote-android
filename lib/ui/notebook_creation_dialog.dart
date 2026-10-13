import 'package:flutter/material.dart';

import '../domain/models/notebook.dart';
import '../repositories/auth_repository.dart';

class NotebookCreationDialog extends StatefulWidget {
  const NotebookCreationDialog({
    super.key,
    required this.repository,
    required this.session,
    required this.notebook,
  });
  final AuthRepository repository;
  final StoredSession session;
  final Notebook notebook;
  @override
  State<NotebookCreationDialog> createState() => _NotebookCreationDialogState();
}

class _NotebookCreationDialogState extends State<NotebookCreationDialog> {
  bool _busy = true;
  String? _state, _error;
  List<Notebook>? _candidates;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final state = await widget.repository.notebookCreationState(
        widget.session,
        widget.notebook.notebookId,
      );
      if (mounted) setState(() => _state = state);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '读取创建状态失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _lookup() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final candidates = await widget.repository.notebookCreationCandidates(
        widget.session,
        widget.notebook.notebookId,
      );
      if (mounted) setState(() => _candidates = candidates);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '查询失败：$error，本地数据已保留');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resolve(Notebook? remote) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(remote == null ? '允许再次创建？' : '关联到这个服务端笔记本？'),
        content: Text(
          remote == null
              ? '请先核实服务端没有创建成功。重复创建可能产生同名笔记本；此操作只恢复待同步状态，不会立即发送请求。'
              : '将“${widget.notebook.title}”及其本地子笔记本、笔记关联到服务端笔记本 ${remote.notebookId}，保留本地未同步内容。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (remote == null) {
        await widget.repository.retryNotebookCreation(
          widget.session,
          widget.notebook.notebookId,
        );
      } else {
        await widget.repository.confirmNotebookCreation(
          widget.session,
          widget.notebook.notebookId,
          remote,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '恢复失败：$error，本地数据已保留');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('笔记本创建状态'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.notebook.title),
              Text(
                _state == 'pending'
                    ? '已保存在本机，等待下次同步创建。可继续添加子笔记本和笔记。'
                    : _state == 'uncertain'
                    ? '创建请求结果未确认，本地数据已保留。不会自动重复创建；请联网查询名称、父级和排序相同的服务端笔记本。'
                    : _state == 'complete'
                    ? '已完成服务端关联，请关闭并刷新。'
                    : '正在读取创建状态。',
              ),
              if (_busy) const LinearProgressIndicator(),
              if (_candidates != null && _candidates!.isEmpty)
                const Text('没有匹配项。可能尚未创建成功，或已被其他客户端修改；请核实后再决定是否重试。'),
              for (final candidate in _candidates ?? <Notebook>[])
                ListTile(
                  title: Text(candidate.title),
                  subtitle: Text(candidate.notebookId),
                  enabled: !_busy,
                  onTap: () => _resolve(candidate),
                ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (_state == 'uncertain') ...[
          TextButton(
            onPressed: _busy ? null : _lookup,
            child: const Text('查询服务端匹配项'),
          ),
          TextButton(
            onPressed: _busy ? null : () => _resolve(null),
            child: const Text('核实后允许重试'),
          ),
        ],
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}
