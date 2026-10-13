import 'package:flutter/material.dart';

import '../data/database/attachment_outbox.dart';
import '../repositories/auth_repository.dart';
import '../services/attachment_exporter.dart';
import 'attachment_upload_dialog.dart';
import 'note_files_page.dart';

class AttachmentOutboxPage extends StatefulWidget {
  const AttachmentOutboxPage({
    super.key,
    required this.repository,
    required this.session,
    this.noteId,
    this.exporter,
  });
  final AuthRepository repository;
  final StoredSession session;
  final String? noteId;
  final AttachmentExporter? exporter;
  @override
  State<AttachmentOutboxPage> createState() => _AttachmentOutboxPageState();
}

class _AttachmentOutboxPageState extends State<AttachmentOutboxPage> {
  List<PendingAttachment> _items = [];
  bool _busy = false;
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
      final items = await widget.repository.pendingAttachments(
        widget.session,
        noteId: widget.noteId,
      );
      if (mounted) setState(() => _items = items);
    } on Object {
      if (mounted) setState(() => _error = '读取本地附件失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
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
      ) ??
      false;

  Future<void> _action(PendingAttachment item, String action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (action == 'files') {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => NoteFilesPage(
              repository: widget.repository,
              session: widget.session,
              noteId: item.noteId,
            ),
          ),
        );
      } else if (action == 'remove') {
        if (await _confirm(
          '移除本地附件？',
          '将删除“${item.name}”的暂存原件及任务，不会删除服务端附件。未上传的文件将无法恢复，请先导出保留。',
        )) {
          await widget.repository.removeStagedAttachment(
            widget.session,
            item.id,
          );
        }
      } else if (action == 'retry') {
        if (await _confirm(
          '重新允许上传？',
          '先查看服务端文件列表，核实“${item.name}”没有上传成功。若原请求已成功，再次上传会产生重复附件。',
        )) {
          await widget.repository.retryUncertainAttachment(
            widget.session,
            item.id,
          );
        }
      } else {
        final file = await widget.repository.stagedAttachment(
          widget.session,
          item.id,
        );
        if (!mounted) return;
        if (action == 'export') {
          await (widget.exporter ?? AttachmentExporter()).save(
            file.name,
            file.bytes,
          );
        } else if (action == 'upload') {
          await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => AttachmentUploadDialog(
              identity: widget.session.account.username,
              file: file,
              upload: (identity, password) =>
                  widget.repository.uploadStagedAttachment(
                    widget.session,
                    item.id,
                    identity: identity,
                    password: password,
                  ),
            ),
          );
        }
      }
      if (mounted) await _load();
    } on Object catch (error) {
      if (mounted) setState(() => _error = '操作未完成：$error。本地原件保留，请刷新核实状态。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('本地待上传附件'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新本地任务',
          ),
        ],
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              '原件保存在本机，不会自动上传或随缓存清理。联网后逐项上传；需要当前密码，密码不保存。上传完成后可移除本地副本。',
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: _items.isEmpty
                ? const Center(child: Text('暂无暂存附件'))
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (_, index) {
                      final item = _items[index];
                      return ListTile(
                        title: Text(item.name),
                        subtitle: Text(
                          '${item.statusLabel} · ${item.size} 字节\n笔记：${item.noteId}',
                        ),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(
                          enabled: !_busy,
                          tooltip: '附件操作',
                          onSelected: (value) => _action(item, value),
                          itemBuilder: (_) => [
                            if (item.state == 'pending')
                              const PopupMenuItem(
                                value: 'upload',
                                child: Text('上传附件'),
                              ),
                            const PopupMenuItem(
                              value: 'files',
                              child: Text('查看服务端文件列表'),
                            ),
                            if (item.state == 'uncertain')
                              const PopupMenuItem(
                                value: 'retry',
                                child: Text('核实后允许重试'),
                              ),
                            const PopupMenuItem(
                              value: 'export',
                              child: Text('导出本地原件'),
                            ),
                            const PopupMenuItem(
                              value: 'remove',
                              child: Text('移除本地附件'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}
