import 'package:flutter/material.dart';

import '../domain/models/note.dart';
import '../domain/models/notebook.dart';
import '../domain/models/notebook_tree.dart';
import '../repositories/auth_repository.dart';
import 'note_editor_page.dart';
import 'note_reader_page.dart';
import 'note_history_page.dart';
import 'note_search_page.dart';
import 'notebook_dialog.dart';
import 'move_notebook_dialog.dart';
import 'account_page.dart';
import 'tags_page.dart';
import 'sync_progress_dialog.dart';
import 'logout_confirmation_dialog.dart';
import 'reset_sync_dialog.dart';

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
  String? _selectedTag;
  var _showingStarred = false;
  var _showingTrash = false;
  var _syncing = false;
  var _loggingOut = false;
  Set<String> _pendingNoteIds = {};
  String? _syncError;
  int _pendingRead = 0;
  final _expandedNotebooks = <String>{};

  @override
  void initState() {
    super.initState();
    _notebooks = widget.repository.notebooks(widget.session.account.cacheKey);
    _refreshPending();
  }

  Future<void> _refreshPending() async {
    final generation = ++_pendingRead;
    try {
      final ids = await widget.repository.pendingNoteIds(
        widget.session.account.cacheKey,
      );
      if (mounted && generation == _pendingRead) {
        setState(() => _pendingNoteIds = ids);
      }
    } on Object catch (error) {
      if (mounted) setState(() => _syncError = '无法读取待同步状态：$error');
    }
  }

  Widget _syncIcon() => Badge(
    isLabelVisible: _pendingNoteIds.isNotEmpty,
    backgroundColor: const Color(0xffb9d9c4),
    child: const Icon(Icons.sync),
  );

  PreferredSizeWidget? get _syncStatus => _syncError == null
      ? null
      : PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              dense: true,
              title: Text(
                _syncError!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                tooltip: '关闭提示',
                onPressed: () => setState(() => _syncError = null),
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        );

  Future<void> _openNotebook(Notebook notebook) async {
    final notes = await widget.repository.notes(
      widget.session.account.cacheKey,
      notebookId: notebook.notebookId,
    );
    if (mounted) {
      setState(() {
        _selectedNotebook = notebook;
        _selectedTag = null;
        _showingStarred = false;
        _showingTrash = false;
        _notes = notes;
      });
    }
  }

  Future<void> _reloadNotes() async {
    await _refreshPending();
    if (_selectedTag != null) {
      final notes = await widget.repository.notesForTag(
        widget.session.account.cacheKey,
        _selectedTag!,
      );
      if (mounted) setState(() => _notes = notes);
      return;
    }
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
    _selectedTag = null;
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
    _selectedTag = null;
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
          onHistory: note.usn == 0
              ? null
              : () async {
                  final restored = await Navigator.of(context).push<bool>(
                    MaterialPageRoute<bool>(
                      builder: (_) => NoteHistoryPage(
                        repository: widget.repository,
                        session: widget.session,
                        note: note,
                      ),
                    ),
                  );
                  if (restored == true && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('历史正文已恢复到本地，待同步')),
                    );
                  }
                  return restored == true;
                },
          onEdit: () => _editNote(note),
          onDeleteForever: note.isTrash ? () => _deleteForever(note) : null,
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

  Future<bool> _deleteForever(Note note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('彻底删除笔记？'),
        content: const Text('此操作无法恢复。下次同步会删除服务端的笔记、历史版本和附件；失败时保留待删除任务。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('彻底删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;
    try {
      await widget.repository.deleteTrash(widget.session, note.noteId);
      await _reloadNotes();
      return true;
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
      return false;
    }
  }

  Future<void> _openTags() async {
    final tag = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => TagsPage(
          repository: widget.repository,
          accountId: widget.session.account.cacheKey,
        ),
      ),
    );
    if (tag == null || !mounted) return;
    try {
      final notes = await widget.repository.notesForTag(
        widget.session.account.cacheKey,
        tag,
      );
      if (!mounted) return;
      setState(() {
        _selectedTag = tag;
        _selectedNotebook = null;
        _showingStarred = false;
        _showingTrash = false;
        _notes = notes;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _syncError = '读取标签笔记失败：$error');
    }
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
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => NoteEditorPage(
          note: note,
          saveText: (title, content) => widget.repository.saveEditedText(
            widget.session,
            note.noteId,
            title,
            content,
          ),
        ),
      ),
    );
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

  Future<void> _sync({bool reset = false}) async {
    if (_syncing || _loggingOut) return;
    setState(() {
      _syncing = true;
      _syncError = null;
    });
    try {
      if (reset && !await confirmResetSync(context)) return;
      if (!mounted) return;
      await showSyncProgress(
        context,
        synchronize: (progress) => reset
            ? widget.repository.resetFromServer(
                widget.session,
                onProgress: progress,
              )
            : widget.repository.synchronize(
                widget.session,
                onProgress: progress,
              ),
      );
      if (!mounted) return;
      _notebooks = widget.repository.notebooks(widget.session.account.cacheKey);
      if (reset) {
        _selectedNotebook = null;
        _selectedTag = null;
        _showingStarred = false;
        _showingTrash = false;
        _notes = [];
        _expandedNotebooks.clear();
      }
      await _reloadNotes();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('同步完成')));
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _syncError = '同步失败：$error');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('同步失败：$error'), backgroundColor: Colors.red),
        );
      }
    } finally {
      await _refreshPending();
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _logout() async {
    if (_loggingOut || _syncing) return;
    setState(() => _loggingOut = true);
    try {
      var leavePending = false;
      try {
        final pending = await widget.repository.pendingNoteIds(
          widget.session.account.cacheKey,
        );
        if (!mounted) return;
        if (pending.isNotEmpty) {
          await showSyncProgress(
            context,
            synchronize: (progress) => widget.repository.prepareLogout(
              widget.session,
              onProgress: progress,
            ),
          );
        }
      } on Object {
        if (!mounted) return;
        leavePending = await confirmUnsyncedLogout(context);
        if (!leavePending) return;
      }
      if (!mounted) return;
      await widget.repository.logout(
        widget.session,
        discardSessionWithPendingChanges: leavePending,
      );
      if (mounted) widget.onSignedOut();
    } on Object catch (error) {
      if (mounted) setState(() => _syncError = '退出登录失败：$error');
    } finally {
      await _refreshPending();
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  Future<void> _moveNotebook(Notebook notebook) async {
    final parent = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MoveNotebookDialog(
        repository: widget.repository,
        session: widget.session,
        notebook: notebook,
      ),
    );
    if (parent == null || !mounted) return;
    final notebooks = await widget.repository.notebooks(
      widget.session.account.cacheKey,
    );
    if (!mounted) return;
    setState(() {
      _notebooks = Future.value(notebooks);
      final byId = {for (final n in notebooks) n.notebookId: n};
      var id = parent;
      final visited = <String>{};
      while (id.isNotEmpty && visited.add(id)) {
        _expandedNotebooks.add(id);
        id = byId[id]?.parentNotebookId ?? '';
      }
    });
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
      if (parentId.isNotEmpty) _expandedNotebooks.add(parentId);
      setState(
        () => _notebooks = widget.repository.notebooks(
          widget.session.account.cacheKey,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedNotebook != null ||
        _selectedTag != null ||
        _showingStarred ||
        _showingTrash) {
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
        bottom: _syncStatus,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: '标签',
            onPressed: _openTags,
            icon: const Icon(Icons.label_outline),
          ),
          IconButton(
            tooltip: '新建笔记本',
            onPressed: () => _editNotebook(),
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'account') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AccountPage(
                      repository: widget.repository,
                      session: widget.session,
                    ),
                  ),
                );
              }
              if (value == 'sync') _sync();
              if (value == 'resetSync') _sync(reset: true);
              if (value == 'trash') _openTrash();
              if (value == 'logout') _logout();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'account', child: Text('账号')),
              PopupMenuItem(value: 'sync', child: Text('立即同步')),
              PopupMenuItem(value: 'resetSync', child: Text('重新同步')),
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
          if (snapshot.hasError) {
            return Center(child: Text('读取笔记本失败：${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final notebooks = snapshot.data!;
          if (notebooks.isEmpty) return const _EmptyState(label: '还没有笔记本');
          final rows = NotebookTree(notebooks).visibleRows(_expandedNotebooks);
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              final notebook = row.notebook;
              return ListTile(
                key: ValueKey(notebook.notebookId),
                contentPadding: EdgeInsets.only(
                  left: 8 + row.depth.clamp(0, 5) * 12.0,
                  right: 8,
                ),
                leading: row.hasChildren
                    ? IconButton(
                        tooltip:
                            _expandedNotebooks.contains(notebook.notebookId)
                            ? '收起子笔记本'
                            : '展开子笔记本',
                        icon: Icon(
                          _expandedNotebooks.contains(notebook.notebookId)
                              ? Icons.expand_more
                              : Icons.chevron_right,
                        ),
                        onPressed: () => setState(() {
                          if (!_expandedNotebooks.remove(notebook.notebookId)) {
                            _expandedNotebooks.add(notebook.notebookId);
                          }
                        }),
                      )
                    : const SizedBox(
                        width: 48,
                        child: Icon(Icons.folder_outlined),
                      ),
                title: Tooltip(
                  message: notebook.title,
                  child: Text(
                    notebook.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
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
                        if (action == 'move') _moveNotebook(notebook);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'rename', child: Text('重命名')),
                        PopupMenuItem(value: 'child', child: Text('新增子笔记本')),
                        PopupMenuItem(value: 'move', child: Text('移动')),
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
              tooltip: _pendingNoteIds.isEmpty
                  ? '立即同步'
                  : '立即同步（${_pendingNoteIds.length} 篇待上传）',
              onPressed: _sync,
              child: _syncIcon(),
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
        bottom: _syncStatus,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() {
            _selectedNotebook = null;
            _selectedTag = null;
            _showingStarred = false;
            _showingTrash = false;
          }),
        ),
        title: Text(
          _selectedTag ??
              (_showingStarred
                  ? '已加星'
                  : _showingTrash
                  ? '回收站'
                  : _selectedNotebook!.title),
        ),
        actions: [
          IconButton(
            tooltip: _syncing ? '正在同步' : '立即同步',
            onPressed: _syncing ? null : _sync,
            icon: _syncing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : _syncIcon(),
          ),
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
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          note.title.isEmpty ? '无标题' : note.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_pendingNoteIds.contains(note.noteId))
                        const Tooltip(
                          message: '本地修改尚未上传',
                          child: Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.circle,
                              size: 8,
                              color: Color(0xff173d38),
                            ),
                          ),
                        ),
                    ],
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
      floatingActionButton:
          _selectedTag != null || _showingStarred || _showingTrash
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
