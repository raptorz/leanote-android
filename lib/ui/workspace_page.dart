import 'package:flutter/material.dart';

import '../domain/models/note.dart';
import '../domain/models/notebook.dart';
import '../repositories/auth_repository.dart';
import 'note_editor_page.dart';
import 'note_reader_page.dart';

class WorkspacePage extends StatefulWidget {
  const WorkspacePage({
    required this.repository,
    required this.session,
    required this.onSignedOut,
    super.key,
  });

  final AuthRepository repository;
  final StoredSession session;
  final VoidCallback onSignedOut;

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  late Future<List<Notebook>> _notebooks;
  List<Note> _notes = const [];
  Notebook? _selectedNotebook;
  var _syncing = false;

  @override
  void initState() {
    super.initState();
    _notebooks = widget.repository.notebooks(widget.session.account.cacheKey);
  }

  Future<void> _openNotebook(Notebook notebook) async {
    final notes = await widget.repository.notes(
      widget.session.account.cacheKey,
      notebookId: notebook.notebookId,
    );
    if (mounted) {
      setState(() {
        _selectedNotebook = notebook;
        _notes = notes;
      });
    }
  }

  Future<void> _reloadNotes() async {
    final notebook = _selectedNotebook;
    if (notebook != null) await _openNotebook(notebook);
  }

  Future<void> _editNote(Note note) async {
    final changed = await Navigator.of(
      context,
    ).push<Note>(MaterialPageRoute(builder: (_) => NoteEditorPage(note: note)));
    if (changed == null) return;
    await widget.repository.saveNote(widget.session, changed);
    await _reloadNotes();
  }

  Future<void> _createNote(bool isMarkdown) async {
    final notebook = _selectedNotebook;
    if (notebook == null) return;
    final note = await widget.repository.createNote(
      widget.session,
      notebookId: notebook.notebookId,
      isMarkdown: isMarkdown,
    );
    await _editNote(note);
  }

  Future<void> _sync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      await widget.repository.synchronize(
        widget.session,
        onProgress: (value) {
          if (mounted) setState(() {});
        },
      );
      _notebooks = widget.repository.notebooks(widget.session.account.cacheKey);
      await _reloadNotes();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('同步完成')));
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('同步失败：$error'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _logout() async {
    await widget.repository.logout(widget.session);
    if (mounted) widget.onSignedOut();
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedNotebook != null) return _buildNoteList(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/images/gemsnote_s.png', width: 32, height: 32),
            const SizedBox(width: 10),
            const Text('珠玑笔记', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: const Color(0xff173d38),
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'sync') _sync();
              if (value == 'logout') _logout();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'account', child: Text('账号')),
              PopupMenuItem(value: 'sync', child: Text('同步')),
              PopupMenuItem(value: 'logout', child: Text('退出')),
            ],
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: CircleAvatar(child: Text(_initials)),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<Notebook>>(
        future: _notebooks,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final notebooks = snapshot.data!;
          if (notebooks.isEmpty) return const _EmptyState(label: '还没有笔记本');
          return ListView.builder(
            itemCount: notebooks.length,
            itemBuilder: (context, index) {
              final notebook = notebooks[index];
              return ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(
                  notebook.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text('${notebook.numberNotes}'),
                onTap: () => _openNotebook(notebook),
              );
            },
          );
        },
      ),
      floatingActionButton: _syncing
          ? const FloatingActionButton(
              onPressed: null,
              child: CircularProgressIndicator(),
            )
          : FloatingActionButton(
              tooltip: '立即同步',
              onPressed: _sync,
              child: const Icon(Icons.sync),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.note_outlined),
            selectedIcon: Icon(Icons.note),
            label: '笔记',
          ),
          NavigationDestination(
            icon: Icon(Icons.star_outline),
            selectedIcon: Icon(Icons.star),
            label: '已加星',
          ),
          NavigationDestination(
            icon: Icon(Icons.share_outlined),
            selectedIcon: Icon(Icons.share),
            label: '共享',
          ),
        ],
      ),
    );
  }

  Widget _buildNoteList(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _selectedNotebook = null),
        ),
        title: Text(_selectedNotebook!.title),
        actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.search))],
      ),
      body: _notes.isEmpty
          ? const _EmptyState(label: '选择笔记或开始全新记录。')
          : ListView.separated(
              itemCount: _notes.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final note = _notes[index];
                return ListTile(
                  leading: Icon(
                    note.isMarkdown ? Icons.code : Icons.article_outlined,
                  ),
                  title: Text(
                    note.title.isEmpty ? '无标题' : note.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(note.updatedTime, maxLines: 1),
                  trailing: note.isStarred
                      ? const Icon(Icons.star, color: Color(0xff816d32))
                      : null,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => NoteReaderPage(
                          note: note,
                          onEdit: () => _editNote(note),
                        ),
                      ),
                    );
                    await _reloadNotes();
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          builder: (context) => SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: const Text('新建笔记'),
                  onTap: () {
                    Navigator.pop(context);
                    _createNote(false);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.code),
                  title: const Text('新建 Markdown'),
                  onTap: () {
                    Navigator.pop(context);
                    _createNote(true);
                  },
                ),
              ],
            ),
          ),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }

  String get _initials {
    final name = widget.session.account.username.trim();
    return name.isEmpty ? '?' : name.characters.first.toUpperCase();
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('assets/images/gemsnote_s.png', width: 72, height: 72),
        const SizedBox(height: 16),
        const Text('日积字句，终得珠玑。', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(label),
      ],
    ),
  );
}
