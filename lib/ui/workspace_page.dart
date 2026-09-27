import 'package:flutter/material.dart';

import '../domain/models/note.dart';
import '../domain/models/notebook.dart';
import '../repositories/auth_repository.dart';
import 'note_editor_page.dart';
import 'note_reader_page.dart';
import 'note_search_page.dart';
import 'notebook_dialog.dart';

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
  var _showingStarred = false;
  var _showingTrash = false;
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
        _showingStarred = false;
        _showingTrash = false;
        _notes = notes;
      });
    }
  }

  Future<void> _reloadNotes() async {
    if (_showingStarred) {
      final notes = await widget.repository.notes(
        widget.session.account.cacheKey,
        starredOnly: true,
      );
      if (mounted) setState(() => _notes = notes);
      return;
    }
    if (_showingTrash) {
      final notes = await widget.repository.notes(
        widget.session.account.cacheKey,
        trashOnly: true,
      );
      if (mounted) setState(() => _notes = notes);
      return;
    }
    final notebook = _selectedNotebook;
    if (notebook != null) await _openNotebook(notebook);
  }

  Future<void> _openStarred() async {
    final notes = await widget.repository.notes(
      widget.session.account.cacheKey,
      starredOnly: true,
    );
    if (mounted) {
      setState(() {
        _selectedNotebook = null;
        _showingStarred = true;
        _showingTrash = false;
        _notes = notes;
      });
    }
  }

  Future<void> _openTrash() async {
    final notes = await widget.repository.notes(
      widget.session.account.cacheKey,
      trashOnly: true,
    );
    if (mounted) {
      setState(() {
        _selectedNotebook = null;
        _showingStarred = false;
        _showingTrash = true;
        _notes = notes;
      });
    }
  }

  Future<void> _openReader(Note note) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NoteReaderPage(
          note: note,
          onEdit: () => _editNote(note),
          onToggleStar: () => _toggleStar(note),
          onMove: () => _moveNote(note),
          onTrashToggle: () => note.isTrash
              ? _saveMetadata(note.copyWith(isTrash: false))
              : _trashNote(note),
        ),
      ),
    );
    await _reloadNotes();
  }

  Future<void> _search() async {
    final note = await Navigator.of(context).push<Note>(
      MaterialPageRoute(
        builder: (_) => NoteSearchPage(
          repository: widget.repository,
          session: widget.session,
        ),
      ),
    );
    if (note != null && mounted) await _openReader(note);
  }

  Future<void> _editNote(Note note) async {
    final changed = await Navigator.of(
      context,
    ).push<Note>(MaterialPageRoute(builder: (_) => NoteEditorPage(note: note)));
    if (changed == null) return;
    await widget.repository.saveNote(widget.session, changed);
    await _reloadNotes();
  }

  Future<void> _saveMetadata(Note note) async {
    await widget.repository.saveNote(
      widget.session,
      note.copyWith(updatedTime: DateTime.now().toUtc().toIso8601String()),
    );
    await _reloadNotes();
  }

  Future<void> _toggleStar(Note note) =>
      _saveMetadata(note.copyWith(isStarred: !note.isStarred));

  Future<void> _moveNote(Note note) async {
    final notebooks = await widget.repository.notebooks(
      widget.session.account.cacheKey,
    );
    if (!mounted) return;
    final selected = await showDialog<Notebook>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('移动到笔记本'),
        children: notebooks
            .map(
              (notebook) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, notebook),
                child: Row(
                  children: [
                    Icon(
                      notebook.notebookId == note.notebookId
                          ? Icons.folder
                          : Icons.folder_outlined,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        notebook.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
    if (selected != null && selected.notebookId != note.notebookId) {
      await _saveMetadata(note.copyWith(notebookId: selected.notebookId));
    }
  }

  Future<void> _trashNote(Note note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移入回收站'),
        content: Text('确定将“${note.title.isEmpty ? '无标题' : note.title}”移入回收站吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移入回收站'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _saveMetadata(note.copyWith(isTrash: true));
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

  Future<void> _editNotebook({Notebook? existing, String parentId = ''}) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NotebookDialog(
        repository: widget.repository,
        session: widget.session,
        existing: existing,
        parentNotebookId: parentId,
      ),
    );
    if (saved == true && mounted) {
      setState(
        () => _notebooks = widget.repository.notebooks(
          widget.session.account.cacheKey,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedNotebook != null || _showingStarred || _showingTrash) {
      return _buildNoteList(context);
    }
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
          IconButton(
            tooltip: '新建笔记本',
            onPressed: () => _editNotebook(),
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'sync') _sync();
              if (value == 'trash') _openTrash();
              if (value == 'logout') _logout();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'account', child: Text('账号')),
              PopupMenuItem(value: 'sync', child: Text('同步')),
              PopupMenuItem(value: 'trash', child: Text('回收站')),
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
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${notebook.numberNotes}'),
                    PopupMenuButton<String>(
                      onSelected: (action) {
                        if (action == 'rename') {
                          _editNotebook(existing: notebook);
                        }
                        if (action == 'child') {
                          _editNotebook(parentId: notebook.notebookId);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'rename', child: Text('重命名')),
                        PopupMenuItem(value: 'child', child: Text('新增子笔记本')),
                      ],
                    ),
                  ],
                ),
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
        onDestinationSelected: (index) {
          if (index == 1) {
            _openStarred();
          } else if (index == 2) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('共享笔记将在后续阶段开放')));
          }
        },
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
          onPressed: () => setState(() {
            _selectedNotebook = null;
            _showingStarred = false;
            _showingTrash = false;
          }),
        ),
        title: Text(
          _showingStarred
              ? '已加星'
              : _showingTrash
              ? '回收站'
              : _selectedNotebook!.title,
        ),
        actions: [
          IconButton(
            tooltip: '搜索笔记',
            onPressed: _search,
            icon: const Icon(Icons.search),
          ),
        ],
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
                  trailing: IconButton(
                    tooltip: note.isStarred ? '取消星标' : '添加星标',
                    onPressed: () => _toggleStar(note),
                    icon: Icon(
                      note.isStarred ? Icons.star : Icons.star_outline,
                      color: note.isStarred ? const Color(0xff816d32) : null,
                    ),
                  ),
                  onTap: () => _openReader(note),
                );
              },
            ),
      floatingActionButton: _showingStarred || _showingTrash
          ? null
          : FloatingActionButton(
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
