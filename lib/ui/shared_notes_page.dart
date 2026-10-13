import 'package:flutter/material.dart';

import '../domain/models/shared_note.dart';
import '../domain/models/shared_file.dart';
import '../domain/models/note_image_reference.dart';
import '../repositories/auth_repository.dart';
import 'note_reader_page.dart';
import 'shared_files_page.dart';

class SharedNotesPage extends StatefulWidget {
  const SharedNotesPage({
    super.key,
    required this.repository,
    required this.session,
  });
  final AuthRepository repository;
  final StoredSession session;
  @override
  State<SharedNotesPage> createState() => _SharedNotesPageState();
}

class _SharedNotesPageState extends State<SharedNotesPage> {
  List<SharedNote> _notes = [];
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
      _notes = [];
    });
    try {
      final notes = await widget.repository.sharedNotes(
        widget.session,
        cachedOnly: _cachedOnly,
      );
      if (mounted && generation == _generation) setState(() => _notes = notes);
    } on Object catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = '读取共享列表失败：$error');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _open(SharedNote note) async {
    if (_opening != null) return;
    setState(() {
      _opening = note.note.noteId;
      _error = null;
    });
    try {
      final content = await widget.repository.sharedContent(
        widget.session,
        note,
        cachedOnly: _cachedOnly,
      );
      if (!mounted) return;
      SharedFile? image(Uri uri) {
        final id = cachedImageFileId(uri, widget.session.account.server);
        return note.files
            .where((file) => file.fileId == id && !file.isAttachment)
            .firstOrNull;
      }

      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => NoteReaderPage(
            note: content,
            readOnly: true,
            safeHtmlPreview: true,
            loadCachedImage: (uri) async {
              final file = image(uri);
              return file == null
                  ? null
                  : widget.repository.cachedSharedFile(
                      widget.session,
                      note,
                      file,
                    );
            },
            canDownloadImage: (uri) =>
                !_cachedOnly &&
                image(uri) != null &&
                image(uri)!.size <= image(uri)!.maxBytes,
            downloadImage: _cachedOnly
                ? null
                : (uri) {
                    final file = image(uri);
                    if (file == null) {
                      return Future.error(StateError('图片不属于共享资源快照'));
                    }
                    return widget.repository.downloadSharedFile(
                      widget.session,
                      note,
                      file,
                    );
                  },
            onFiles: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => SharedFilesPage(
                  repository: widget.repository,
                  session: widget.session,
                  note: note,
                  cachedOnly: _cachedOnly,
                ),
              ),
            ),
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = '读取共享正文失败：$error');
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('共享笔记'),
      actions: [
        IconButton(
          tooltip: '刷新共享列表',
          onPressed: _loading || _opening != null ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        SwitchListTile(
          title: const Text('离线缓存'),
          subtitle: const Text('缓存可能已过期；离线时无法确认共享权限是否已撤销。'),
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
          child: Text('只读浏览；已查看的正文和已下载的图片附件可离线使用。文件操作会核实在线共享权限和版本。'),
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
          child: !_loading && _notes.isEmpty
              ? Center(
                  child: Text(
                    _error == null
                        ? (_cachedOnly ? '暂无缓存的共享笔记' : '暂无共享笔记')
                        : '请刷新重试',
                  ),
                )
              : ListView.builder(
                  itemCount: _notes.length,
                  itemBuilder: (context, index) {
                    final shared = _notes[index];
                    return ListTile(
                      title: Text(
                        shared.note.title.isEmpty ? '无标题' : shared.note.title,
                      ),
                      subtitle: Text('共享者：${shared.note.userId}'),
                      trailing: _opening == shared.note.noteId
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(),
                            )
                          : null,
                      onTap: _opening == null ? () => _open(shared) : null,
                    );
                  },
                ),
        ),
      ],
    ),
  );
}
