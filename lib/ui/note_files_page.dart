import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../domain/models/note_file.dart';
import '../repositories/auth_repository.dart';
import '../services/image_exporter.dart';
import '../services/attachment_exporter.dart';
import '../services/attachment_sharer.dart';
import '../services/file_cache_batch.dart';
import '../services/attachment_picker.dart';
import 'attachment_upload_dialog.dart';

class NoteFilesPage extends StatefulWidget {
  const NoteFilesPage({
    super.key,
    required this.repository,
    required this.session,
    required this.noteId,
    this.imageExporter,
    this.attachmentExporter,
    this.attachmentPicker,
    this.attachmentSharer,
  });
  final AuthRepository repository;
  final StoredSession session;
  final String noteId;
  final ImageExporter? imageExporter;
  final AttachmentExporter? attachmentExporter;
  final AttachmentPicker? attachmentPicker;
  final AttachmentSharer? attachmentSharer;
  @override
  State<NoteFilesPage> createState() => _NoteFilesPageState();
}

class _NoteFilesPageState extends State<NoteFilesPage> {
  List<NoteFile> _files = [];
  bool _loading = false;
  String? _opening;
  String? _error;
  bool _cachedOnly = false;
  int _generation = 0;
  FileCacheBatch? _batch;
  FileCacheProgress? _batchProgress;
  List<NoteFile> _failedFiles = [];
  String? _batchMessage;

  @override
  void dispose() {
    _batch?.cancel();
    super.dispose();
  }

  Future<void> _cacheFiles({bool retry = false}) async {
    if (_batch != null || _loading || _opening != null || _cachedOnly) return;
    final files = List<NoteFile>.of(retry ? _failedFiles : _files);
    if (files.isEmpty) return;
    final batch = FileCacheBatch();
    setState(() {
      _batch = batch;
      _batchMessage = null;
      _error = null;
      _failedFiles = [];
    });
    final result = await batch.run(
      files,
      download: (file) async {
        if (file.isAttachment) {
          await widget.repository.noteAttachment(
            widget.session,
            widget.noteId,
            file,
          );
        } else {
          await widget.repository.noteImage(
            widget.session,
            widget.noteId,
            file,
          );
        }
      },
      onProgress: (progress) {
        if (mounted) setState(() => _batchProgress = progress);
      },
    );
    if (!mounted) return;
    setState(() {
      _batch = null;
      _failedFiles = result.failed;
      _batchMessage =
          '${result.cancelled ? "已停止" : "下载处理完成"}：已处理 ${result.completed} 个，失败 ${result.failed.length} 个。缓存最多 64 MiB，较早文件可能被淘汰。';
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_opening != null || _batch != null) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _files = [];
      _failedFiles = [];
      _batchProgress = null;
      _batchMessage = null;
    });
    try {
      final files = await widget.repository.noteFiles(
        widget.session,
        widget.noteId,
        cachedOnly: _cachedOnly,
      );
      if (mounted && generation == _generation) setState(() => _files = files);
    } on Object catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = '读取文件列表失败：$error');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _open(NoteFile file) async {
    if (_opening != null || _batch != null || file.isAttachment) return;
    setState(() {
      _opening = file.id;
      _error = null;
    });
    try {
      final bytes = await widget.repository.noteImage(
        widget.session,
        widget.noteId,
        file,
        cachedOnly: _cachedOnly,
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => _ImagePreview(
            title: file.title,
            bytes: bytes,
            exporter: widget.imageExporter ?? ImageExporter(),
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = '读取图片失败：$error');
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  Future<void> _uploadAttachment() async {
    if (_cachedOnly || _loading || _opening != null || _batch != null) return;
    setState(() => _opening = 'upload');
    try {
      final file = await (widget.attachmentPicker ?? AttachmentPicker()).pick();
      if (!mounted || file == null) return;
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AttachmentUploadDialog(
          identity: widget.session.account.username,
          file: file,
          upload: (identity, password) => widget.repository.uploadAttachment(
            widget.session,
            widget.noteId,
            file,
            identity: identity,
            password: password,
          ),
        ),
      );
      if (!mounted || result == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result ? '附件已上传' : '附件已上传，但本地刷新失败，请同步后刷新文件列表，勿重复上传'),
        ),
      );
      setState(() => _opening = null);
      await _load();
    } on Object catch (error) {
      if (mounted) setState(() => _error = '无法上传附件：$error');
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  Future<void> _shareAttachment(NoteFile file) async {
    if (_loading || _opening != null || _batch != null || !file.isAttachment) {
      return;
    }
    setState(() {
      _opening = file.id;
      _error = null;
    });
    try {
      final bytes = await widget.repository.noteAttachment(
        widget.session,
        widget.noteId,
        file,
        cachedOnly: _cachedOnly,
      );
      if (!mounted) return;
      // Resolve the current page bounds after download, including any rotation.
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) throw StateError('无法定位分享窗口');
      final origin = box.localToGlobal(Offset.zero) & box.size;
      await (widget.attachmentSharer ?? AttachmentSharer()).share(
        file.title,
        bytes,
        origin,
      );
    } on Object {
      if (mounted) {
        setState(
          () => _error = _cachedOnly
              ? '分享附件失败：附件未缓存、缓存已失效或无法打开分享菜单，请联网下载后重试'
              : '分享附件失败，请检查网络、文件权限或系统分享功能后重试（最大 32 MiB）',
        );
      }
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  Future<void> _saveAttachment(NoteFile file) async {
    if (_opening != null || _batch != null) return;
    setState(() {
      _opening = file.id;
      _error = null;
    });
    try {
      final bytes = await widget.repository.noteAttachment(
        widget.session,
        widget.noteId,
        file,
        cachedOnly: _cachedOnly,
      );
      if (!mounted) return;
      final saved = await (widget.attachmentExporter ?? AttachmentExporter())
          .save(file.title, bytes);
      if (mounted && saved) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('附件已保存')));
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = _cachedOnly
              ? '保存附件失败：附件未缓存、缓存已失效或无法写入保存位置，请联网下载后重试'
              : '保存附件失败，请检查网络、文件权限或保存位置后重试（最大 32 MiB）',
        );
      }
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('图片与附件'),
      actions: [
        IconButton(
          tooltip: '上传附件',
          icon: const Icon(Icons.upload_file),
          onPressed:
              _cachedOnly || _loading || _opening != null || _batch != null
              ? null
              : _uploadAttachment,
        ),
        IconButton(
          tooltip: '刷新文件列表',
          onPressed: _loading || _opening != null || _batch != null
              ? null
              : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        SwitchListTile(
          title: const Text('离线缓存'),
          subtitle: const Text('仅查看缓存，可能不是最新内容；未缓存图片需联网查看。'),
          value: _cachedOnly,
          onChanged: _opening != null || _batch != null
              ? null
              : (value) {
                  setState(() => _cachedOnly = value);
                  _load();
                },
        ),
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            '图片最多 8 MiB，附件最多 32 MiB，缓存合计 64 MiB。已下载附件可离线保存，取消系统保存也保留缓存。联网刷新会清除本笔记旧文件缓存。',
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (!_cachedOnly) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text('批量缓存会使用网络流量，最多并行下载 3 个文件；离开页面将停止安排后续下载。'),
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed:
                    _loading ||
                        _opening != null ||
                        _batch != null ||
                        _files.isEmpty
                    ? null
                    : () => _cacheFiles(),
                icon: const Icon(Icons.download),
                label: const Text('缓存当前笔记文件'),
              ),
              if (_failedFiles.isNotEmpty)
                TextButton(
                  onPressed: _batch != null
                      ? null
                      : () => _cacheFiles(retry: true),
                  child: const Text('重试失败文件'),
                ),
              if (_batch != null)
                TextButton(
                  onPressed: () {
                    _batch?.cancel();
                    setState(() => _batchMessage = '正在停止，等待已开始的下载结束…');
                  },
                  child: const Text('停止下载'),
                ),
            ],
          ),
        ],
        if (_batch != null && _batchProgress != null) ...[
          LinearProgressIndicator(
            value: _batchProgress!.total == 0
                ? 0
                : _batchProgress!.completed / _batchProgress!.total,
          ),
          Text(
            '已处理 ${_batchProgress!.completed}/${_batchProgress!.total}，失败 ${_batchProgress!.failed}',
          ),
        ],
        if (_batchMessage != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_batchMessage!),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: !_loading && _files.isEmpty
              ? Center(child: Text(_error == null ? '暂无图片或附件' : '请刷新重试'))
              : ListView.builder(
                  itemCount: _files.length,
                  itemBuilder: (_, index) {
                    final file = _files[index];
                    return ListTile(
                      leading: Icon(
                        file.isAttachment
                            ? Icons.attach_file
                            : Icons.image_outlined,
                      ),
                      title: Text(file.title.isEmpty ? file.id : file.title),
                      subtitle: Text(
                        file.isAttachment
                            ? '附件 · ${file.type}'
                            : '图片 · ${file.type}',
                      ),
                      trailing: _opening == file.id
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(),
                            )
                          : file.isAttachment
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: '保存附件',
                                  icon: const Icon(Icons.save_alt),
                                  onPressed: _opening != null || _batch != null
                                      ? null
                                      : () => _saveAttachment(file),
                                ),
                                IconButton(
                                  tooltip: '分享附件',
                                  icon: const Icon(Icons.share_outlined),
                                  onPressed: _opening != null || _batch != null
                                      ? null
                                      : () => _shareAttachment(file),
                                ),
                              ],
                            )
                          : null,
                      onTap: _opening != null || _batch != null
                          ? null
                          : () => file.isAttachment
                                ? _saveAttachment(file)
                                : _open(file),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}

class _ImagePreview extends StatefulWidget {
  const _ImagePreview({
    required this.title,
    required this.bytes,
    required this.exporter,
  });
  final String title;
  final Uint8List bytes;
  final ImageExporter exporter;
  @override
  State<_ImagePreview> createState() => _ImagePreviewState();
}

class _ImagePreviewState extends State<_ImagePreview> {
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final saved = await widget.exporter.save(widget.title, widget.bytes);
      if (mounted && saved) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('图片已保存')));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存图片失败，请检查保存位置或可用空间后重试')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title.isEmpty ? '图片' : widget.title),
      actions: [
        IconButton(
          tooltip: _saving ? '正在保存…' : '保存图片',
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_alt),
        ),
      ],
    ),
    body: Center(
      child: InteractiveViewer(
        child: Image(
          image: ResizeImage(
            MemoryImage(widget.bytes),
            width: 2048,
            height: 2048,
            policy: ResizeImagePolicy.fit,
          ),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const Text('无法解码图片，请返回重试'),
        ),
      ),
    ),
  );
}
