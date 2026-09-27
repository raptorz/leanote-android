import 'package:flutter/material.dart';

import '../domain/models/note.dart';
import '../domain/models/note_history.dart';
import '../repositories/auth_repository.dart';
import 'note_reader_page.dart';

class NoteHistoryPage extends StatefulWidget {
  const NoteHistoryPage({
    super.key,
    required this.repository,
    required this.session,
    required this.note,
  });
  final AuthRepository repository;
  final StoredSession session;
  final Note note;
  @override
  State<NoteHistoryPage> createState() => _NoteHistoryPageState();
}

class _NoteHistoryPageState extends State<NoteHistoryPage> {
  late Future<List<NoteHistory>> _histories;
  String? _loading;
  String? _error;
  @override
  void initState() {
    super.initState();
    _histories = _load();
  }

  Future<List<NoteHistory>> _load() =>
      widget.repository.histories(widget.session, widget.note.noteId);

  Future<void> _open(NoteHistory history) async {
    if (_loading != null) return;
    setState(() {
      _loading = history.id;
      _error = null;
    });
    try {
      final content = await widget.repository.historyContent(
        widget.session,
        widget.note.noteId,
        history.id,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NoteReaderPage(
            readOnly: true,
            note: widget.note.copyWith(
              content: content,
              updatedTime: history.updatedTime,
              title: '${widget.note.title} · 历史版本',
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = '读取历史正文失败：$error');
    } finally {
      if (mounted) setState(() => _loading = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('历史版本')),
    body: Column(
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: FutureBuilder<List<NoteHistory>>(
            future: _histories,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('读取历史版本失败：${snapshot.error}'),
                      TextButton(
                        onPressed: () => setState(() => _histories = _load()),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = snapshot.data!;
              if (items.isEmpty) return const Center(child: Text('暂无历史版本'));
              return ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final history = items[index];
                  return ListTile(
                    key: ValueKey(history.id),
                    title: Text(history.updatedTime),
                    subtitle: Text('修改用户：${history.updatedUserId}'),
                    trailing: _loading == history.id
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: _loading == null ? () => _open(history) : null,
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}
