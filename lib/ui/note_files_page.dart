import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../domain/models/note_file.dart';
import '../repositories/auth_repository.dart';

class NoteFilesPage extends StatefulWidget {
  const NoteFilesPage({
    super.key,
    required this.repository,
    required this.session,
    required this.noteId,
  });
  final AuthRepository repository;
  final StoredSession session;
  final String noteId;
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
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_opening != null) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _files = [];
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
    if (_opening != null || file.isAttachment) return;
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
          builder: (_) => _ImagePreview(title: file.title, bytes: bytes),
        ),
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = '读取图片失败：$error');
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
          tooltip: '刷新文件列表',
          onPressed: _loading || _opening != null ? null : _load,
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
          onChanged: _opening != null
              ? null
              : (value) {
                  setState(() => _cachedOnly = value);
                  _load();
                },
        ),
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            '已查看图片可离线预览（每张最多 8 MiB，缓存总计 64 MiB）。联网刷新会清除本笔记旧图片缓存。附件暂仅显示列表。',
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
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
                          : null,
                      onTap: file.isAttachment || _opening != null
                          ? null
                          : () => _open(file),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.title, required this.bytes});
  final String title;
  final Uint8List bytes;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title.isEmpty ? '图片' : title)),
    body: Center(
      child: InteractiveViewer(
        child: Image(
          image: ResizeImage(
            MemoryImage(bytes),
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
