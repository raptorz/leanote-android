import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../domain/models/shared_file.dart';
import '../domain/models/shared_note.dart';
import '../repositories/auth_repository.dart';
import '../services/attachment_exporter.dart';
import '../services/attachment_opener.dart';
import '../services/attachment_sharer.dart';
import '../services/image_exporter.dart';

class SharedFilesPage extends StatefulWidget {
  const SharedFilesPage({
    super.key,
    required this.repository,
    required this.session,
    required this.note,
    required this.cachedOnly,
    this.attachmentExporter,
    this.attachmentOpener,
    this.attachmentSharer,
    this.imageExporter,
  });
  final AuthRepository repository;
  final StoredSession session;
  final SharedNote note;
  final bool cachedOnly;
  final AttachmentExporter? attachmentExporter;
  final AttachmentOpener? attachmentOpener;
  final AttachmentSharer? attachmentSharer;
  final ImageExporter? imageExporter;
  @override
  State<SharedFilesPage> createState() => _SharedFilesPageState();
}

class _SharedFilesPageState extends State<SharedFilesPage> {
  String? _busy;
  String? _error;

  Future<void> _act(SharedFile file, String action, Rect origin) async {
    if (_busy != null) return;
    setState(() {
      _busy = file.fileId;
      _error = null;
    });
    try {
      final Uint8List bytes;
      if (widget.cachedOnly) {
        final cached = await widget.repository.cachedSharedFile(
          widget.session,
          widget.note,
          file,
        );
        if (cached == null) throw StateError('文件尚未缓存，请联网下载');
        bytes = cached;
      } else {
        bytes = await widget.repository.downloadSharedFile(
          widget.session,
          widget.note,
          file,
        );
      }
      if (!mounted) return;
      switch (action) {
        case 'download':
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('文件已缓存，可离线使用')));
        case 'save':
          final saved = file.isAttachment
              ? await (widget.attachmentExporter ?? AttachmentExporter()).save(
                  file.title,
                  bytes,
                )
              : await (widget.imageExporter ?? ImageExporter()).save(
                  file.title,
                  bytes,
                );
          if (mounted && saved) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('文件已保存')));
          }
        case 'open':
          await (widget.attachmentOpener ?? AttachmentOpener()).open(
            file.title,
            bytes,
            canOpen: () => mounted,
          );
        case 'share':
          await (widget.attachmentSharer ?? AttachmentSharer()).share(
            file.title,
            bytes,
            origin,
          );
        case 'preview':
          await Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: Text(file.title)),
                body: Center(
                  child: InteractiveViewer(
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      cacheWidth: 2048,
                      errorBuilder: (_, _, _) => const Text('图片无法解码'),
                    ),
                  ),
                ),
              ),
            ),
          );
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = '读取共享文件失败：$error');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('共享图片与附件')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            widget.cachedOnly
                ? '离线使用已下载的文件；无法离线确认共享权限是否撤销。'
                : '操作时核实共享权限和文件版本；图片最多 8 MiB，附件最多 32 MiB。',
          ),
        ),
        if (_busy != null) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: widget.note.files.isEmpty
              ? const Center(child: Text('暂无共享资源'))
              : ListView.builder(
                  itemCount: widget.note.files.length,
                  itemBuilder: (context, index) {
                    final file = widget.note.files[index];
                    final supported = file.size <= file.maxBytes;
                    return ListTile(
                      leading: Icon(
                        file.isAttachment
                            ? Icons.attach_file
                            : Icons.image_outlined,
                      ),
                      title: Text(
                        file.title.isEmpty ? file.fileId : file.title,
                      ),
                      subtitle: Text(
                        '${file.size} B${supported ? '' : ' · 超出移动端大小限制'}',
                      ),
                      trailing: Builder(
                        builder: (anchor) => PopupMenuButton<String>(
                          tooltip: '文件操作',
                          enabled: _busy == null && supported,
                          onSelected: (action) {
                            final box = anchor.findRenderObject();
                            if (box is RenderBox && box.hasSize) {
                              _act(
                                file,
                                action,
                                box.localToGlobal(Offset.zero) & box.size,
                              );
                            }
                          },
                          itemBuilder: (_) => [
                            if (!widget.cachedOnly)
                              const PopupMenuItem(
                                value: 'download',
                                child: Text('下载到缓存'),
                              ),
                            if (!file.isAttachment)
                              const PopupMenuItem(
                                value: 'preview',
                                child: Text('查看图片'),
                              ),
                            const PopupMenuItem(
                              value: 'save',
                              child: Text('保存到文件'),
                            ),
                            if (file.isAttachment)
                              const PopupMenuItem(
                                value: 'open',
                                child: Text('用其他应用打开'),
                              ),
                            const PopupMenuItem(
                              value: 'share',
                              child: Text('系统分享'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}
