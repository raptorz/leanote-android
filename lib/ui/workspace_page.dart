import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/models/note.dart';
import '../domain/models/note_image_reference.dart';
import '../domain/models/note_sort.dart';
import '../domain/models/notebook.dart';
import '../domain/models/notebook_tree.dart';
import '../repositories/auth_repository.dart';
import '../services/note_exporter.dart';
import '../services/note_sharer.dart';
import 'note_editor_page.dart';
import 'import_note_dialog.dart';
import 'note_reader_page.dart';
import 'note_files_page.dart';
import 'notebook_target_picker.dart';
import 'note_tags_dialog.dart';
import 'note_history_page.dart';
import 'note_search_page.dart';
import 'notebook_dialog.dart';
import 'move_notebook_dialog.dart';
import 'account_page.dart';
import 'account_avatar.dart';
import 'shared_notes_page.dart';
import 'tags_page.dart';
import 'sync_progress_dialog.dart';
import 'logout_confirmation_dialog.dart';
import 'reset_sync_dialog.dart';

class WorkspacePage extends StatefulWidget {
  const WorkspacePage({
    required this.repository,
    required this.session,
    required this.onSignedOut,
    this.refreshAvatarOnStart = false,
    super.key,
  });

  final AuthRepository repository;
  final StoredSession session;
  final VoidCallback onSignedOut;
  final bool refreshAvatarOnStart;

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage>
    with WidgetsBindingObserver {
  late Future<List<Notebook>> _notebooks;
  List<Note> _notes = const [];
  Notebook? _selectedNotebook;
  String? _selectedTag;
  var _showingStarred = false;
  var _showingTrash = false;
  var _showingAll = false;
  var _noteSort = NoteSort.updatedDescending;
  var _syncing = false;
  var _loggingOut = false;
  Set<String> _pendingNoteIds = {};
  String? _syncError;
  int _pendingRead = 0;
  Uint8List? _avatar;
  int _avatarRead = 0;
  String? _avatarError;
  bool _refreshingAvatar = false;
  final _expandedNotebooks = <String>{};
  Timer? _autoSyncTimer;
  bool _autoSyncEnabled = false;
  bool _signedOut = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _notebooks = widget.repository.notebooks(widget.session.account.cacheKey);
    _refreshPending();
    _refreshAvatarCache();
    if (widget.refreshAvatarOnStart) unawaited(_refreshRemoteAvatar());
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _scheduleAutoSync();
  }

  void _toggleAutoSync() {
    setState(() => _autoSyncEnabled = !_autoSyncEnabled);
    _scheduleAutoSync();
  }

  void _scheduleAutoSync() {
    _autoSyncTimer?.cancel();
    if (!_autoSyncEnabled || !_foreground || _signedOut) return;
    // Do not synchronize immediately on enable/resume. In particular, choosing
    // to skip synchronization at login remains meaningful.
    _autoSyncTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted || _signedOut || !_foreground || _syncing || _loggingOut) {
        return;
      }
      // Editors, readers, account pages and confirmation/menu routes must not
      // be interrupted by automatic refreshes of their underlying note data.
      if (ModalRoute.of(context)?.isCurrent != true) return;
      unawaited(_sync(automatic: true));
    });
  }

  Future<void> _refreshRemoteAvatar() async {
    if (_refreshingAvatar || _loggingOut) return;
    _refreshingAvatar = true;
    try {
      await widget.repository.refreshAccountPresentation(widget.session);
      if (!mounted) return;
      setState(() => _avatarError = null);
      await _refreshAvatarCache();
    } on Object catch (error) {
      if (mounted) setState(() => _avatarError = '头像刷新失败（不影响笔记同步）：$error');
    } finally {
      _refreshingAvatar = false;
    }
  }

  Future<void> _refreshAvatarCache() async {
    final generation = ++_avatarRead;
    try {
      final bytes = await widget.repository.cachedAvatar(widget.session);
      if (mounted && generation == _avatarRead) {
        setState(() => _avatar = bytes);
      }
    } on Object catch (error) {
      if (mounted && generation == _avatarRead) {
        setState(() => _syncError = '读取头像缓存失败：$error');
      }
    }
  }

  Future<void> _openAccount() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            AccountPage(repository: widget.repository, session: widget.session),
      ),
    );
    if (mounted) await _refreshAvatarCache();
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

  PreferredSizeWidget? get _syncStatus =>
      _syncError == null && _avatarError == null
      ? null
      : PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              dense: true,
              title: Text(
                _syncError ?? _avatarError!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                tooltip: '关闭提示',
                onPressed: () => setState(() {
                  _syncError = null;
                  _avatarError = null;
                }),
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
    if (_showingAll) {
      await _openAllNotes();
      return;
    }
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

  Future<void> _openAllNotes() async {
    try {
      final notes = await widget.repository.notes(
        widget.session.account.cacheKey,
      );
      if (!mounted) return;
      setState(() {
        _selectedNotebook = null;
        _selectedTag = null;
        _showingStarred = false;
        _showingTrash = false;
        _showingAll = true;
        _notes = notes;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _syncError = '读取所有笔记失败：$error');
    }
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
          onExport: () => NoteExporter().export(note),
          onSystemShare: (origin) => NoteSharer().share(note, origin),
          canDownloadImage: (uri) =>
              note.usn > 0 &&
              cachedImageFileId(uri, widget.session.account.server) != null,
          downloadImage: (uri) => widget.repository.downloadInlineImage(
            widget.session,
            note.noteId,
            uri,
          ),
          loadCachedImage: (uri) => widget.repository.cachedInlineImage(
            widget.session,
            note.noteId,
            uri,
          ),
          onFiles: note.usn <= 0
              ? null
              : () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => NoteFilesPage(
                      repository: widget.repository,
                      session: widget.session,
                      noteId: note.noteId,
                    ),
                  ),
                ),
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
          onEditTags: () async =>
              await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (_) => NoteTagsDialog(
                  tags: note.tags,
                  loadSuggestions: () => widget.repository.tagCounts(
                    widget.session.account.cacheKey,
                  ),
                  onSave: (tags) => widget.repository.saveNoteTags(
                    widget.session,
                    note.noteId,
                    tags,
                  ),
                ),
              ) ==
              true,
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
    String? target;
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('移动到笔记本'),
          content: SizedBox(
            width: 320,
            height: 320,
            child: NotebookTargetPicker(
              notebooks: notebooks,
              selected: target,
              canSelect: (id) => id != note.notebookId,
              onSelected: (id) => update(() => target = id),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: target == null
                  ? null
                  : () => Navigator.pop(context, target),
              child: const Text('移动'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );
    if (selected != null && selected != note.notebookId) {
      await _saveMetadata(note.copyWith(notebookId: selected));
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

  Future<void> _importNote() async {
    final book = _selectedNotebook;
    if (book == null || _syncing || _loggingOut) return;
    final note = await showDialog<Note>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ImportNoteDialog(
        onImport: (source) async {
          final books = await widget.repository.notebooks(
            widget.session.account.cacheKey,
          );
          if (!books.any(
            (item) => item.notebookId == book.notebookId && !item.isDeleted,
          )) {
            throw StateError('目标笔记本已不存在，请返回重新选择');
          }
          return widget.repository.createNote(
            widget.session,
            notebookId: book.notebookId,
            isMarkdown: source.isMarkdown,
            title: source.title,
            content: source.content,
          );
        },
      ),
    );
    if (note == null || !mounted) return;
    await _reloadNotes();
    await _refreshPending();
    if (mounted) await _openReader(note);
  }

  Future<void> _sync({
    bool reset = false,
    bool full = false,
    bool automatic = false,
  }) async {
    if (_syncing || _loggingOut || _signedOut) return;
    setState(() {
      _syncing = true;
      _syncError = null;
    });
    try {
      if (reset && !await confirmResetSync(context)) return;
      if (!mounted) return;
      if (automatic) {
        await widget.repository.synchronize(widget.session);
      } else {
        await showSyncProgress(
          context,
          synchronize: (progress) => reset
              ? widget.repository.resetFromServer(
                  widget.session,
                  onProgress: progress,
                )
              : full
              ? widget.repository.synchronizeFull(
                  widget.session,
                  onProgress: progress,
                )
              : widget.repository.synchronize(
                  widget.session,
                  onProgress: progress,
                ),
        );
      }
      if (!mounted) return;
      _notebooks = widget.repository.notebooks(widget.session.account.cacheKey);
      await _refreshAvatarCache();
      if (!mounted) return;
      if (reset) {
        _selectedNotebook = null;
        _selectedTag = null;
        _showingStarred = false;
        _showingTrash = false;
        _notes = [];
        _expandedNotebooks.clear();
      }
      await _reloadNotes();
      unawaited(_refreshRemoteAvatar());
      if (mounted && !automatic) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('同步完成')));
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _syncError = '同步失败：$error');
        if (!automatic) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('同步失败：$error'), backgroundColor: Colors.red),
          );
        }
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
      _signedOut = true;
      _autoSyncTimer?.cancel();
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
        _showingAll ||
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
            tooltip: '账号菜单',
            onSelected: (value) {
              if (value == 'account') {
                _openAccount();
              }
              if (value == 'sync') _sync();
              if (value == 'fullSync') _sync(full: true);
              if (value == 'resetSync') _sync(reset: true);
              if (value == 'autoSync') _toggleAutoSync();
              if (value == 'trash') _openTrash();
              if (value == 'logout') _logout();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'account', child: Text('账号')),
              const PopupMenuItem(value: 'sync', child: Text('立即同步')),
              const PopupMenuItem(value: 'fullSync', child: Text('完全同步（合并）')),
              CheckedPopupMenuItem(
                value: 'autoSync',
                checked: _autoSyncEnabled,
                child: const Text('前台自动同步（每分钟）'),
              ),
              const PopupMenuItem(value: 'resetSync', child: Text('重新同步')),
              const PopupMenuItem(value: 'trash', child: Text('回收站')),
              const PopupMenuItem(value: 'logout', child: Text('退出')),
            ],
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: AccountAvatar(bytes: _avatar),
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
          final rows = NotebookTree(notebooks).visibleRows(_expandedNotebooks);
          return ListView.builder(
            itemCount: rows.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return ListTile(
                  leading: const Icon(Icons.notes),
                  title: const Text('所有笔记'),
                  onTap: _openAllNotes,
                );
              }
              final row = rows[index - 1];
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
            Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => SharedNotesPage(
                  repository: widget.repository,
                  session: widget.session,
                ),
              ),
            );
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
    final sortedNotes = _noteSort.apply(_notes);
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
            _showingAll = false;
          }),
        ),
        title: Text(
          _showingAll
              ? '所有笔记'
              : _selectedTag ??
                    (_showingStarred
                        ? '已加星'
                        : _showingTrash
                        ? '回收站'
                        : _selectedNotebook!.title),
        ),
        actions: [
          PopupMenuButton<NoteSort>(
            tooltip: '笔记排序',
            icon: const Icon(Icons.sort),
            onSelected: (value) => setState(() => _noteSort = value),
            itemBuilder: (_) => [
              for (final sort in NoteSort.values)
                CheckedPopupMenuItem(
                  value: sort,
                  checked: sort == _noteSort,
                  child: Text(sort.label),
                ),
            ],
          ),
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
                final note = sortedNotes[index];
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
          _showingAll ||
              _selectedTag != null ||
              _showingStarred ||
              _showingTrash
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
                      ListTile(
                        leading: const Icon(Icons.file_open_outlined),
                        title: const Text('导入笔记原文'),
                        onTap: _syncing || _loggingOut
                            ? null
                            : () {
                                Navigator.pop(context);
                                _importNote();
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
