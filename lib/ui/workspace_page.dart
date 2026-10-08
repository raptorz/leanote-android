import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/models/note.dart';
import '../domain/models/default_editor.dart';
import 'default_editor_dialog.dart';
import '../domain/models/note_image_reference.dart';
import '../domain/models/note_sort.dart';
import '../domain/models/notebook.dart';
import '../domain/models/notebook_tree.dart';
import '../repositories/auth_repository.dart';
import '../services/note_exporter.dart';
import '../services/shared_text_inbox.dart';
import 'shared_text_dialog.dart';
import '../services/note_sharer.dart';
import '../services/account_file_cache.dart';
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
import 'about_dialog.dart';
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
    this.sharedTextInbox,
    super.key,
  });

  final AuthRepository repository;
  final StoredSession session;
  final VoidCallback onSignedOut;
  final bool refreshAvatarOnStart;
  final SharedTextInbox? sharedTextInbox;

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
  bool _accountOpen = false;
  bool _foreground = true;
  bool _autoCacheFiles = false;
  AccountFileCache? _fileQueue;
  Future<void>? _fileTask;
  String? _fileStatus;

  late final SharedTextInbox _shareInbox;
  bool _shareOpen = false;

  void _shareChanged() {
    if (mounted) setState(() {});
  }

  Widget get _shareButton => IconButton(
    tooltip: '待处理分享',
    icon: Badge(
      isLabelVisible: _shareInbox.pending != null || _shareInbox.error != null,
      child: const Icon(Icons.move_to_inbox_outlined),
    ),
    onPressed: _syncing || _loggingOut || _shareOpen ? null : _openSharedText,
  );

  Future<void> _openSharedText() async {
    if (_shareOpen || _syncing || _loggingOut || _signedOut) return;
    _shareOpen = true;
    try {
      await _shareInbox.refresh();
      if (_shareInbox.error != null) throw StateError(_shareInbox.error!);
      final source = _shareInbox.pending;
      if (!mounted) return;
      if (source == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('没有待处理分享')));
        return;
      }
      final books = await widget.repository.notebooks(
        widget.session.account.cacheKey,
      );
      if (!mounted) return;
      final note = await showDialog<Note>(
        context: context,
        barrierDismissible: false,
        builder: (_) => SharedTextDialog(
          source: source,
          notebooks: books,
          accountLabel:
              '${widget.session.account.username} · ${widget.session.account.server}',
          canImport:
              source.accountKey.isEmpty ||
              source.accountKey == widget.session.account.cacheKey,
          onImport: (edited, notebookId) async {
            await _shareInbox.claim(source, widget.session.account.cacheKey);
            return widget.repository.importSharedText(
              widget.session,
              edited,
              notebookId,
            );
          },
          onAcknowledge: () => _shareInbox.acknowledge(source),
        ),
      );
      if (note != null && mounted) {
        await _reloadNotes();
        await _refreshPending();
        if (mounted) await _openReader(note);
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('读取分享失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _shareOpen = false);
    }
  }

  Future<void> _stopFileCache() async {
    _fileQueue?.cancel();
    await _fileTask;
  }

  void _startFileCache() {
    if (!_autoCacheFiles ||
        !_foreground ||
        _signedOut ||
        _loggingOut ||
        _fileTask != null) {
      return;
    }
    final queue = _fileQueue = AccountFileCache();
    setState(() => _fileStatus = '正在准备离线资源缓存…');
    _fileTask = (() async {
      try {
        final notes = await widget.repository.notes(
          widget.session.account.cacheKey,
        );
        await queue.run(
          notes.where((n) => n.usn > 0).map((n) => n.noteId).toList(),
          listFiles: (id) => widget.repository.noteFiles(widget.session, id),
          download: (id, file) async {
            if (file.isAttachment) {
              await widget.repository.noteAttachment(widget.session, id, file);
            } else {
              await widget.repository.noteImage(widget.session, id, file);
            }
          },
          onProgress: (notes, files, failures) {
            if (mounted) {
              setState(
                () =>
                    _fileStatus = '资源缓存：已处理 $notes 篇、$files 个文件，失败 $failures 项',
              );
            }
          },
        );
        if (mounted) {
          setState(
            () => _fileStatus =
                '${_fileStatus ?? "资源缓存"}（${queue.cancelled ? "已停止" : "已结束"}；缓存限额 64 MiB）',
          );
        }
      } on Object catch (error) {
        if (mounted) setState(() => _fileStatus = '资源缓存失败（不影响笔记同步）：$error');
      } finally {
        _fileQueue = null;
        _fileTask = null;
      }
    })();
  }

  @override
  void initState() {
    super.initState();
    _shareInbox = widget.sharedTextInbox ?? SharedTextInbox();
    _shareInbox.addListener(_shareChanged);
    unawaited(_shareInbox.start());
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
    _fileQueue?.cancel();
    _autoSyncTimer?.cancel();
    _shareInbox.removeListener(_shareChanged);
    _shareInbox.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(_shareInbox.refresh());
    if (!_foreground) _fileQueue?.cancel();
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
    if (_syncing || _loggingOut || _signedOut || _accountOpen) return;
    _accountOpen = true;
    try {
      await _stopFileCache();
      if (!mounted) return;
      final signedOut = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => AccountPage(
            repository: widget.repository,
            session: widget.session,
          ),
        ),
      );
      if (signedOut == true && mounted) {
        _signedOut = true;
        _autoSyncTimer?.cancel();
        widget.onSignedOut();
        return;
      }
      if (mounted) await _refreshAvatarCache();
    } finally {
      _accountOpen = false;
    }
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
      _syncError == null && _avatarError == null && _fileStatus == null
      ? null
      : PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Material(
            color: _syncError != null || _avatarError != null
                ? Theme.of(context).colorScheme.errorContainer
                : Theme.of(context).colorScheme.secondaryContainer,
            child: ListTile(
              dense: true,
              title: Text(
                _syncError ?? _avatarError ?? _fileStatus!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                tooltip: '关闭提示',
                onPressed: () => setState(() {
                  _syncError = null;
                  _avatarError = null;
                  _fileStatus = null;
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
    if (mounted) {
      setState(() {
        _notebooks = widget.repository.notebooks(
          widget.session.account.cacheKey,
        );
      });
    }
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
          onCopy: () => _moveNote(note, copy: true),
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
          identity: widget.session.account.email.isNotEmpty
              ? widget.session.account.email
              : widget.session.account.username,
          uploadImage: (image, identity, password) async {
            await _stopFileCache();
            return widget.repository.uploadNoteImage(
              widget.session,
              note.noteId,
              image,
              identity: identity,
              password: password,
            );
          },
          loadCachedImage: (uri) => widget.repository.cachedInlineImage(
            widget.session,
            note.noteId,
            uri,
          ),
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

  Future<bool> _moveNote(Note note, {bool copy = false}) async {
    try {
      final notebooks = await widget.repository.notebooks(
        widget.session.account.cacheKey,
      );
      if (!mounted) return false;
      String? target;
      final selected = await showDialog<String>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(copy ? '复制到笔记本' : '移动到笔记本'),
            content: SizedBox(
              width: 320,
              height: 320,
              child: NotebookTargetPicker(
                notebooks: notebooks,
                selected: target,
                canSelect: (id) => copy || id != note.notebookId,
                onSelected: (id) => update(() => target = id),
              ),
            ),
            actions: [
              FilledButton(
                onPressed: target == null
                    ? null
                    : () => Navigator.pop(context, target),
                child: Text(copy ? '复制' : '移动'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ],
          ),
        ),
      );
      if (selected != null && copy) {
        await widget.repository.copyNote(widget.session, note, selected);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('笔记已复制到本地，待同步')));
        }
        return true;
      }
      if (selected != null && selected != note.notebookId) {
        await _saveMetadata(note.copyWith(notebookId: selected));
        return true;
      }
      return false;
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('操作失败：$error')));
      }
      return false;
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

  bool _createMenuOpen = false;

  Future<void> _chooseDefaultEditor() => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => DefaultEditorDialog(
      load: () => widget.repository.defaultEditor(widget.session),
      save: (editor) =>
          widget.repository.setDefaultEditor(widget.session, editor),
    ),
  );

  Future<void> _showCreateMenu() async {
    if (_createMenuOpen ||
        _syncing ||
        _loggingOut ||
        _selectedNotebook == null) {
      return;
    }
    setState(() => _createMenuOpen = true);
    try {
      final editor = await widget.repository.defaultEditor(widget.session);
      if (!mounted) return;
      final alternate = editor == DefaultEditor.html
          ? DefaultEditor.markdown
          : DefaultEditor.html;
      final action = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.note_add_outlined),
                title: const Text('新建笔记'),
                subtitle: Text('默认：${editor.label}'),
                onTap: () => Navigator.pop(context, editor.name),
              ),
              ListTile(
                leading: Icon(
                  alternate.isMarkdown ? Icons.code : Icons.article_outlined,
                ),
                title: Text('新建${alternate.isMarkdown ? " Markdown" : "富文本"}'),
                onTap: () => Navigator.pop(context, alternate.name),
              ),
              ListTile(
                leading: const Icon(Icons.file_open_outlined),
                title: const Text('导入笔记原文'),
                onTap: () => Navigator.pop(context, 'import'),
              ),
            ],
          ),
        ),
      );
      if (!mounted || action == null) return;
      if (action == 'import') {
        await _importNote();
      } else {
        await _createNote(DefaultEditor.values.byName(action).isMarkdown);
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('新建笔记失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _createMenuOpen = false);
    }
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
    if (_syncing || _loggingOut || _signedOut || _accountOpen) return;
    setState(() {
      _syncing = true;
      _syncError = null;
    });
    try {
      if (reset && !await confirmResetSync(context)) return;
      // Drain in-flight resource writes before replacing or merging snapshots.
      // Otherwise a late file list could repopulate a freshly reset cache.
      await _stopFileCache();
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
      if (mounted) _startFileCache();
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
      await _stopFileCache();
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
      setState(() {
        _notebooks = widget.repository.notebooks(
          widget.session.account.cacheKey,
        );
      });
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
            const Expanded(
              child: Text(
                '珠玑笔记',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xff173d38),
        bottom: _syncStatus,
        foregroundColor: Colors.white,
        actions: [
          if (_shareInbox.supported) _shareButton,
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
              if (value == 'defaultEditor') _chooseDefaultEditor();
              if (value == 'account') {
                _openAccount();
              }
              if (value == 'sync') _sync();
              if (value == 'fullSync') _sync(full: true);
              if (value == 'resetSync') _sync(reset: true);
              if (value == 'autoSync') _toggleAutoSync();
              if (value == 'autoCache') {
                setState(() => _autoCacheFiles = !_autoCacheFiles);
                if (!_autoCacheFiles) _fileQueue?.cancel();
              }
              if (value == 'cacheFiles' && !_syncing && !_loggingOut) {
                _startFileCache();
              }
              if (value == 'stopCache') _fileQueue?.cancel();
              if (value == 'trash') _openTrash();
              if (value == 'about') {
                showDialog<void>(
                  context: context,
                  builder: (_) => const MobileAboutDialog(),
                );
              }
              if (value == 'logout') _logout();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'account', child: Text('账号')),
              const PopupMenuItem(value: 'defaultEditor', child: Text('默认编辑器')),
              const PopupMenuItem(value: 'sync', child: Text('立即同步')),
              const PopupMenuItem(value: 'fullSync', child: Text('完全同步（合并）')),
              CheckedPopupMenuItem(
                value: 'autoCache',
                checked: _autoCacheFiles,
                child: const Text('同步后缓存图片和附件（本次会话）'),
              ),
              if (_autoCacheFiles && _fileTask == null)
                const PopupMenuItem(value: 'cacheFiles', child: Text('开始资源缓存')),
              if (_fileTask != null)
                const PopupMenuItem(value: 'stopCache', child: Text('停止资源缓存')),
              CheckedPopupMenuItem(
                value: 'autoSync',
                checked: _autoSyncEnabled,
                child: const Text('前台自动同步（每分钟）'),
              ),
              const PopupMenuItem(value: 'resetSync', child: Text('重新同步')),
              const PopupMenuItem(value: 'trash', child: Text('回收站')),
              const PopupMenuItem(value: 'about', child: Text('关于')),
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
          if (_shareInbox.supported) _shareButton,
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
              onPressed: _createMenuOpen || _syncing || _loggingOut
                  ? null
                  : _showCreateMenu,
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
