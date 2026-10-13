import 'dart:typed_data';
import 'dart:ui' as ui;

import '../core/api/api2_client.dart';
import '../core/api/api_exception.dart';
import '../data/database/app_database.dart';
import '../data/session/session_store.dart';
import '../domain/models/account.dart';
import '../domain/models/default_editor.dart';
import '../domain/models/attachment_upload.dart';
import '../domain/models/note.dart';
import '../domain/models/note_sort.dart';
import '../domain/models/note_file.dart';
import '../domain/models/file_cache_usage.dart';
import '../domain/models/note_image_reference.dart';
import '../domain/models/note_history.dart';
import '../domain/models/notebook.dart';
import '../domain/models/notebook_tree.dart';
import '../domain/models/shared_note.dart';
import '../sync/sync_coordinator.dart';
import '../services/note_image_picker.dart';
import '../services/shared_text_inbox.dart';

class StoredSession {
  const StoredSession({required this.account, required this.token});

  final Account account;
  final String token;
}

class PendingLogin {
  const PendingLogin({required this.session, required this.hasCache});

  final StoredSession session;
  final bool hasCache;
}

class AuthRepository {
  AuthRepository(this._api, this._database, this._sessions, this._sync);

  final Map<String, Future<void>> _presentationRefreshes = {};
  final Map<String, Future<List<SharedNote>>> _sharedRefreshes = {};
  final Map<String, Future<List<NoteFile>>> _fileRefreshes = {};
  final Map<String, Future<Uint8List>> _inlineDownloads = {};

  Future<void> refreshAccountPresentation(StoredSession session) {
    final key = session.account.cacheKey;
    return _presentationRefreshes[key] ??=
        (() async {
          final profile = await refreshProfile(session);
          await refreshAvatar(session, profile);
        })().whenComplete(() {
          _presentationRefreshes.remove(key);
        });
  }

  final Api2Client _api;
  final AppDatabase _database;
  final SessionStore _sessions;
  Future<Uint8List> downloadInlineImage(
    StoredSession session,
    String noteId,
    Uri uri,
  ) {
    final id = cachedImageFileId(uri, session.account.server);
    if (id == null) return Future.error(StateError('不支持下载此图片地址'));
    final key = '${session.account.cacheKey}:$noteId:$id';
    return _inlineDownloads[key] ??=
        (() async {
          var files = await _database.cachedNoteFiles(
            session.account.cacheKey,
            noteId,
          );
          if (!files.any((file) => file.id == id && !file.isAttachment)) {
            files = await noteFiles(session, noteId);
          }
          for (final file in files) {
            if (file.id == id && !file.isAttachment) {
              return noteImage(session, noteId, file);
            }
          }
          throw StateError('图片不属于当前笔记，请同步后重试');
        })().whenComplete(() {
          _inlineDownloads.remove(key);
        });
  }

  Future<Uint8List?> cachedInlineImage(
    StoredSession session,
    String noteId,
    Uri uri,
  ) async {
    final id = cachedImageFileId(uri, session.account.server);
    if (id == null) return null;
    final files = await _database.cachedNoteFiles(
      session.account.cacheKey,
      noteId,
    );
    for (final file in files) {
      if (file.id == id && !file.isAttachment) {
        try {
          return await _database.cachedNoteImage(
            session.account.cacheKey,
            noteId,
            file,
          );
        } on StateError {
          return null;
        }
      }
    }
    return null;
  }

  Future<List<NoteFile>> noteFiles(
    StoredSession session,
    String noteId, {
    bool cachedOnly = false,
  }) async {
    if (cachedOnly) {
      return _database.cachedNoteFiles(session.account.cacheKey, noteId);
    }
    final key = '${session.account.cacheKey}:$noteId';
    return _fileRefreshes[key] ??=
        (() async {
          try {
            final files = await _api.noteFiles(
              server: session.account.server,
              token: session.token,
              noteId: noteId,
              userId: session.account.userId,
            );
            await _database.replaceNoteFiles(
              session.account.cacheKey,
              noteId,
              files,
            );
          } on ApiException catch (error) {
            if (error.code == 'notExists' || error.code == 'noPermission') {
              await _database.replaceNoteFiles(
                session.account.cacheKey,
                noteId,
                [],
              );
            }
            rethrow;
          }
          return _database.cachedNoteFiles(session.account.cacheKey, noteId);
        })().whenComplete(() {
          _fileRefreshes.remove(key);
        });
  }

  /// Creates a resource only. The editor must save the returned reference in
  /// its local body; ordinary note sync then establishes server membership.
  Future<String> uploadNoteImage(
    StoredSession session,
    String noteId,
    NoteImageUpload image, {
    required String identity,
    required String password,
  }) async {
    if (identity.trim().isEmpty || password.isEmpty) {
      throw const FormatException('请输入当前账号和密码');
    }
    late String reference;
    await _sync.runAttachmentUpload(
      () async {
        final local = (await _database.notes(session.account.cacheKey))
            .where((note) => note.noteId == noteId)
            .firstOrNull;
        if (local == null ||
            local.userId != session.account.userId ||
            local.isTrash ||
            local.isDeleted ||
            local.usn <= 0 ||
            (await _database.pendingNoteIds(session.account.cacheKey))
                .contains(noteId)) {
          throw StateError('请先同步此笔记，再上传图片');
        }
        reference = await _api.uploadNoteImage(
          server: session.account.server,
          token: session.token,
          userId: session.account.userId,
          identity: identity,
          password: password,
          noteId: noteId,
          image: image,
        );
      },
      account: session.account,
      token: session.token,
      noteId: noteId,
    );
    return reference;
  }

  /// True means upload and cache refresh succeeded; false means upload was
  /// confirmed but refresh failed. Never repeat the upload to retry refresh.
  Future<bool> uploadAttachment(
    StoredSession session,
    String noteId,
    AttachmentUpload file, {
    required String identity,
    required String password,
  }) async {
    var refreshed = false;
    if (identity.trim().isEmpty || password.isEmpty) {
      throw const FormatException('请输入当前账号和密码');
    }
    await _sync.runAttachmentUpload(
      () async {
        final local = (await _database.notes(session.account.cacheKey))
            .where((note) => note.noteId == noteId)
            .firstOrNull;
        if (local == null ||
            local.userId != session.account.userId ||
            local.usn <= 0 ||
            (await _database.pendingNoteIds(session.account.cacheKey))
                .contains(noteId)) {
          throw StateError('请先同步此笔记，再上传附件');
        }
        await _api.uploadAttachment(
          server: session.account.server,
          token: session.token,
          userId: session.account.userId,
          identity: identity,
          password: password,
          noteId: noteId,
          file: file,
        );
        try {
          final pending = _fileRefreshes['${session.account.cacheKey}:$noteId'];
          if (pending != null) await pending;
          final snapshot = await _api.getConflictSnapshot(
            server: session.account.server,
            token: session.token,
            noteId: noteId,
          );
          if (snapshot.note.userId != session.account.userId) {
            throw StateError('accountMismatch');
          }
          await _database.mergeChanges(
            account: session.account,
            notebooks: [],
            notes: [snapshot.note],
            tags: [],
            lastSyncUsn: await _database.lastSyncUsn(session.account.cacheKey),
          );
          await noteFiles(session, noteId);
          refreshed = true;
        } on Object {
          // Remote mutation succeeded. Report refresh separately from upload.
        }
      },
      account: session.account,
      token: session.token,
      noteId: noteId,
    );
    return refreshed;
  }

  Future<Uint8List> noteImage(
    StoredSession session,
    String noteId,
    NoteFile file, {
    bool cachedOnly = false,
  }) async {
    if (cachedOnly) {
      return _database.cachedNoteImage(session.account.cacheKey, noteId, file);
    }
    try {
      final bytes = await _api.noteImage(
        server: session.account.server,
        token: session.token,
        noteId: noteId,
        userId: session.account.userId,
        file: file,
      );
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 256);
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
      await _database.cacheNoteImage(
        session.account.cacheKey,
        noteId,
        file,
        bytes,
      );
      return bytes;
    } on ApiException catch (error) {
      if ({
        'notExists',
        'noPermission',
        'imageNotInNote',
      }.contains(error.code)) {
        await _database.replaceNoteFiles(session.account.cacheKey, noteId, []);
      }
      rethrow;
    }
  }

  Future<Uint8List> noteAttachment(
    StoredSession session,
    String noteId,
    NoteFile file, {
    bool cachedOnly = false,
  }) async {
    if (cachedOnly) {
      return _database.cachedNoteAttachment(
        session.account.cacheKey,
        noteId,
        file,
      );
    }
    try {
      final bytes = await _api.noteAttachment(
        server: session.account.server,
        token: session.token,
        noteId: noteId,
        userId: session.account.userId,
        file: file,
      );
      await _database.cacheNoteAttachment(
        session.account.cacheKey,
        noteId,
        file,
        bytes,
      );
      return bytes;
    } on ApiException catch (error) {
      if ({
        'notExists',
        'noPermission',
        'attachmentNotInNote',
      }.contains(error.code)) {
        await _database.replaceNoteFiles(session.account.cacheKey, noteId, []);
      }
      rethrow;
    }
  }

  final SyncCoordinator _sync;

  Future<List<SharedNote>> sharedNotes(
    StoredSession session, {
    bool cachedOnly = false,
  }) async {
    if (cachedOnly) {
      return _database.cachedSharedNotes(session.account.cacheKey);
    }
    final key = session.account.cacheKey;
    return _sharedRefreshes[key] ??=
        (() async {
          final notes = await _api.sharedNotes(
            server: session.account.server,
            token: session.token,
          );
          await _database.replaceSharedSnapshot(key, notes);
          return notes;
        })().whenComplete(() {
          _sharedRefreshes.remove(key);
        });
  }

  Future<Note> sharedContent(
    StoredSession session,
    SharedNote note, {
    bool cachedOnly = false,
  }) async {
    if (cachedOnly) {
      return _database.cachedSharedContent(session.account.cacheKey, note);
    }
    try {
      final content = await _api.sharedContent(
        server: session.account.server,
        token: session.token,
        shared: note,
      );
      await _database.cacheSharedContent(
        session.account.cacheKey,
        note,
        content.content,
      );
      return content;
    } on ApiException catch (error) {
      if (error.code == 'noPermission' ||
          error.code == 'notExists' ||
          error.code == 'sharedContentChanged') {
        await _database.removeSharedNote(
          session.account.cacheKey,
          note.note.noteId,
        );
      }
      rethrow;
    }
  }

  Future<List<Account>> savedAccounts() async {
    final result = <Account>[];
    for (final account in await _database.cachedAccounts()) {
      final token = await _sessions.read(account.cacheKey);
      if (token != null && token.isNotEmpty) result.add(account);
    }
    return result;
  }

  /// Switching is local: keep dirty rows and credentials for every other account.
  Future<StoredSession> switchAccount(String accountKey) async {
    if (_sync.isBusy) throw StateError('syncInProgress');
    final accounts = await _database.cachedAccounts();
    final account = accounts.where((a) => a.cacheKey == accountKey).firstOrNull;
    if (account == null) throw StateError('accountCacheMissing');
    final token = await _sessions.read(accountKey);
    if (token == null || token.isEmpty) {
      throw StateError('accountLoginRequired');
    }
    if (_sync.isBusy) throw StateError('syncInProgress');
    await _database.activateCachedAccount(account);
    return StoredSession(account: account, token: token);
  }

  Future<StoredSession?> restore() async {
    final account = await _database.activeAccount();
    if (account == null) return null;
    final token = await _sessions.read(account.cacheKey);
    if (token == null || token.isEmpty) return null;
    return StoredSession(account: account, token: token);
  }

  Future<PendingLogin> beginLogin({
    required String serverAddress,
    required String identity,
    required String password,
  }) async {
    final server = normalizeServer(serverAddress);
    final result = await _api.login(
      server: server,
      identity: identity.trim(),
      password: password,
    );
    _validateCompatibility(result);
    final cached = await _database.hasAccountCache(result.account.cacheKey);
    return PendingLogin(
      session: StoredSession(account: result.account, token: result.token),
      hasCache: cached,
    );
  }

  Future<StoredSession> completeLogin(
    PendingLogin login, {
    required bool resetCache,
    SyncProgressCallback? onProgress,
  }) async {
    final previous = await _database.activeAccount();
    try {
      final session = login.session;
      if (login.hasCache && resetCache) {
        await _sync.resetFromServer(
          account: session.account,
          token: session.token,
          onProgress: onProgress,
        );
      } else if (!login.hasCache) {
        await _sync.downloadFreshSnapshot(
          account: session.account,
          token: session.token,
          onProgress: onProgress,
        );
      }
      await _sessions.write(session.account.cacheKey, session.token);
      await _database.activateCachedAccount(session.account);
      return session;
    } on Object {
      // A fresh snapshot may have activated the new account before secure
      // storage failed. Keep the visible account and restart behavior consistent.
      if (previous != null) {
        await _database.activateCachedAccount(previous);
      } else {
        await _database.deactivate(login.session.account.cacheKey);
      }
      rethrow;
    }
  }

  Future<void> prepareLogout(
    StoredSession session, {
    SyncProgressCallback? onProgress,
  }) async {
    if (_sync.metadataUpdating) throw StateError('metadataUpdateInProgress');
    if (_sync.attachmentUploading) {
      throw StateError('attachmentUploadInProgress');
    }
    if ((await pendingNoteIds(session.account.cacheKey)).isEmpty &&
        (await _database.dirtyNotebooks(session.account.cacheKey)).isEmpty) {
      return;
    }
    await _sync.uploadPending(
      account: session.account,
      token: session.token,
      onProgress: onProgress,
    );
    if ((await pendingNoteIds(session.account.cacheKey)).isNotEmpty ||
        (await _database.dirtyNotebooks(session.account.cacheKey)).isNotEmpty) {
      throw StateError('unsyncedChanges');
    }
  }

  Future<void> logout(
    StoredSession session, {
    bool discardSessionWithPendingChanges = false,
  }) async {
    if (_sync.metadataUpdating) throw StateError('metadataUpdateInProgress');
    if (_sync.attachmentUploading) {
      throw StateError('attachmentUploadInProgress');
    }
    if (!discardSessionWithPendingChanges &&
        ((await pendingNoteIds(session.account.cacheKey)).isNotEmpty ||
            (await _database.dirtyNotebooks(session.account.cacheKey))
                .isNotEmpty)) {
      throw StateError('unsyncedChanges');
    }
    // Local logout retains the account cache and never waits on the network.
    await _sessions.delete(session.account.cacheKey);
    await _database.deactivate(session.account.cacheKey);
  }

  Future<List<Notebook>> notebooks(String accountId) =>
      _database.notebooks(accountId);

  Future<Account> cachedProfile(StoredSession session) =>
      _database.cachedProfile(session.account);

  Future<Uint8List?> cachedAvatar(StoredSession session) =>
      _database.cachedAvatar(session.account.cacheKey);

  Future<Uint8List?> refreshAvatar(
    StoredSession session,
    Account profile,
  ) async {
    if (profile.cacheKey != session.account.cacheKey) {
      throw const ApiException('accountMismatch');
    }
    final bytes = await _api.downloadAvatar(
      server: profile.server,
      logo: profile.logo,
    );
    if (bytes != null) {
      // Validate before replacing a working cache with a bogus image response.
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 256);
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
    }
    await _database.cacheAvatar(session.account.cacheKey, bytes);
    return bytes;
  }

  Future<Account> refreshProfile(StoredSession session) async {
    final profile = await _api.userInfo(
      server: session.account.server,
      token: session.token,
    );
    if (profile.userId != session.account.userId) {
      throw const ApiException('accountMismatch');
    }
    await _database.updateProfile(profile);
    return profile;
  }

  Future<void> restoreHistory(
    StoredSession session,
    String noteId,
    String historyId, {
    bool cachedOnly = false,
  }) async {
    final content = await historyContent(
      session,
      noteId,
      historyId,
      cachedOnly: cachedOnly,
    );
    await _database.restoreHistoryContent(
      session.account.cacheKey,
      noteId,
      content,
    );
  }

  Future<List<NoteHistory>> histories(
    StoredSession session,
    String noteId, {
    bool cachedOnly = false,
  }) async {
    if (cachedOnly) {
      return _database.cachedHistories(session.account.cacheKey, noteId);
    }
    final items = await _api.getHistories(
      server: session.account.server,
      token: session.token,
      noteId: noteId,
    );
    await _database.cacheHistories(session.account.cacheKey, noteId, items);
    return items;
  }

  Future<String> historyContent(
    StoredSession session,
    String noteId,
    String historyId, {
    bool cachedOnly = false,
  }) async {
    if (cachedOnly) {
      return _database.cachedHistoryContent(
        session.account.cacheKey,
        noteId,
        historyId,
      );
    }
    final content = await _api.getHistoryContent(
      server: session.account.server,
      token: session.token,
      noteId: noteId,
      historyId: historyId,
    );
    await _database.cacheHistoryContent(
      session.account.cacheKey,
      noteId,
      historyId,
      content,
    );
    return content;
  }

  Future<void> updateUsername(
    StoredSession session, {
    required String identity,
    required String password,
    required String username,
  }) {
    if (identity.trim().isEmpty ||
        password.isEmpty ||
        username.trim().isEmpty) {
      throw const FormatException('请填写登录账号、当前密码和新用户名');
    }
    return _api.updateUsername(
      server: session.account.server,
      userId: session.account.userId,
      identity: identity.trim(),
      password: password,
      username: username.trim(),
    );
  }

  Future<void> requestEmailChange(
    StoredSession session, {
    required String identity,
    required String password,
    required String email,
  }) {
    final trimmed = email.trim();
    if (identity.trim().isEmpty ||
        password.isEmpty ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(trimmed)) {
      throw const FormatException('请填写当前账号、密码及有效的新邮箱');
    }
    // Do not update cached email until the user confirms the emailed link.
    return _api.requestEmailChange(
      server: session.account.server,
      userId: session.account.userId,
      identity: identity.trim(),
      password: password,
      email: trimmed,
    );
  }

  Future<void> changePassword(
    StoredSession session, {
    required String identity,
    required String oldPassword,
    required String password,
  }) {
    if (identity.trim().isEmpty || oldPassword.isEmpty || password.isEmpty) {
      throw const FormatException('请填写当前账号、当前密码及新密码');
    }
    return _api.changePassword(
      server: session.account.server,
      userId: session.account.userId,
      identity: identity.trim(),
      oldPassword: oldPassword,
      password: password,
    );
  }

  Future<void> uploadAvatar(
    StoredSession session, {
    required String identity,
    required String password,
    required Uint8List bytes,
  }) {
    if (identity.trim().isEmpty || password.isEmpty) {
      throw const FormatException('请填写当前账号和密码');
    }
    return _api.uploadAvatar(
      server: session.account.server,
      userId: session.account.userId,
      identity: identity.trim(),
      password: password,
      bytes: bytes,
    );
  }

  Future<void> queueNotebookRename(
    StoredSession session,
    String notebookId,
    String title,
  ) => _database.editLocalNotebook(
    session.account.cacheKey,
    notebookId,
    title: title,
  );

  Future<void> queueNotebookMove(
    StoredSession session,
    String notebookId,
    String parentId,
  ) => _database.editLocalNotebook(
    session.account.cacheKey,
    notebookId,
    parentId: parentId,
  );

  Future<void> saveNotebook(
    StoredSession session, {
    required String title,
    Notebook? existing,
    String? parentNotebookId,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) throw const FormatException('请输入笔记本名称');
    if (existing != null &&
        (await _database.dirtyNotebooks(session.account.cacheKey))
            .any((n) => n.notebookId == existing.notebookId)) {
      throw StateError('notebookHasPendingChanges');
    }
    final notebook = await _api.saveNotebook(
      server: session.account.server,
      token: session.token,
      title: trimmed,
      existing: existing,
      parentNotebookId: parentNotebookId,
    );
    await _database.cacheNotebook(session.account.cacheKey, notebook);
  }

  Future<void> moveNotebook(
    StoredSession session,
    String notebookId,
    String parentId,
  ) async {
    final current = await notebooks(session.account.cacheKey);
    if (!canMoveNotebook(current, notebookId, parentId)) {
      throw const FormatException('目标笔记本无效，不能移到自身、子级或循环层级下');
    }
    final source = current.firstWhere((n) => n.notebookId == notebookId);
    if (source.parentNotebookId == parentId) return;
    if (source.isDirty) throw StateError('notebookHasPendingChanges');
    final moved = await _api.saveNotebook(
      server: session.account.server,
      token: session.token,
      title: source.title,
      existing: source,
      parentNotebookId: parentId,
    );
    if (moved.parentNotebookId != parentId || moved.isDeleted) {
      throw const ApiException('invalidResponse');
    }
    await _database.cacheNotebook(session.account.cacheKey, moved);
  }

  Future<List<Note>> notes(
    String accountId, {
    String? notebookId,
    bool starredOnly = false,
    bool trashOnly = false,
  }) => _database.notes(
    accountId,
    notebookId: notebookId,
    starredOnly: starredOnly,
    trashOnly: trashOnly,
  );

  Future<Map<String, int>> tagCounts(String accountId) =>
      _database.tagCounts(accountId);

  Future<Map<String, int>> availableTags(String accountId) =>
      _database.tagCounts(accountId, includeUnused: true);

  Future<void> createTag(StoredSession session, String value) async {
    final name = value.trim();
    if (name.isEmpty ||
        name.runes.length > 200 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(name)) {
      throw const FormatException('标签名称需为 1–200 个字符，且不能包含换行或控制字符');
    }
    await _sync.runMetadataUpdate(() async {
      final usn = await _api.createTag(
        server: session.account.server,
        token: session.token,
        userId: session.account.userId,
        name: name,
      );
      await _database.cacheTag(session.account.cacheKey, name, usn);
    });
  }

  Future<List<Note>> notesForTag(String accountId, String tag) =>
      _database.notesForTag(accountId, tag);

  Future<Set<String>> pendingNoteIds(String accountId) =>
      _database.pendingNoteIds(accountId);

  Future<List<Note>> searchNotes(
    String accountId,
    String query, {
    int limit = 50,
  }) => _database.searchNotes(accountId, query, limit: limit);

  Future<FileCacheUsage> fileCacheUsage(StoredSession session) =>
      _database.fileCacheUsage(session.account.cacheKey);

  Future<void> clearFileCache(StoredSession session) =>
      _database.clearFileCache(session.account.cacheKey);

  Future<bool> autoCacheFiles(StoredSession session) =>
      _database.autoCacheFiles(session.account.cacheKey);

  Future<void> setAutoCacheFiles(StoredSession session, bool enabled) =>
      _database.setAutoCacheFiles(session.account.cacheKey, enabled);

  Future<NoteSort> noteSort(StoredSession session) =>
      _database.noteSort(session.account.cacheKey);

  Future<void> setNoteSort(StoredSession session, NoteSort sort) =>
      _database.setNoteSort(session.account.cacheKey, sort);

  Future<DefaultEditor> defaultEditor(StoredSession session) =>
      _database.defaultEditor(session.account.cacheKey);

  Future<void> setDefaultEditor(StoredSession session, DefaultEditor editor) =>
      _database.setDefaultEditor(session.account.cacheKey, editor);

  Future<Note> createNote(
    StoredSession session, {
    required String notebookId,
    required bool isMarkdown,
    String title = '',
    String content = '',
  }) => _database.createLocalNote(
    account: session.account,
    notebookId: notebookId,
    isMarkdown: isMarkdown,
    title: title,
    content: content,
  );

  Future<Note> importSharedText(
    StoredSession session,
    SharedText source,
    String notebookId,
  ) {
    if (source.accountKey.isNotEmpty &&
        source.accountKey != session.account.cacheKey) {
      throw StateError('此分享已指定其他账号');
    }
    return _database.importSharedText(
      account: session.account,
      shareId: source.id,
      notebookId: notebookId,
      title: source.suggestedTitle,
      content: source.text,
    );
  }

  Future<Note> copyNote(
    StoredSession session,
    Note source,
    String notebookId,
  ) async {
    if (source.userId != session.account.userId) {
      throw StateError('只能复制当前账号的个人笔记');
    }
    // An empty local cache is not proof that the server has no attachments.
    final files = source.usn > 0
        ? await _api.noteFiles(
            server: session.account.server,
            token: session.token,
            noteId: source.noteId,
            userId: session.account.userId,
          )
        : <NoteFile>[];
    if (files.isNotEmpty) throw StateError('暂不支持复制带图片或附件的笔记');
    return _database.copyLocalNote(
      account: session.account,
      source: source,
      notebookId: notebookId,
      filesConfirmedEmpty: true,
    );
  }

  Future<void> saveEditedText(
    StoredSession session,
    String noteId,
    String title,
    String content,
  ) => _database.saveEditedText(
    session.account.cacheKey,
    noteId,
    title,
    content,
  );

  Future<void> deleteTrash(StoredSession session, String noteId) =>
      _database.deleteLocalTrash(session.account.cacheKey, noteId);

  Future<void> saveNoteTags(
    StoredSession session,
    String noteId,
    List<String> tags,
  ) => _database.saveNoteTags(session.account.cacheKey, noteId, tags);

  Future<void> saveNote(StoredSession session, Note note) =>
      _database.saveLocalNote(session.account.cacheKey, note);

  Future<void> resetFromServer(
    StoredSession session, {
    SyncProgressCallback? onProgress,
  }) async {
    final profile = await cachedProfile(session);
    await _sync.resetFromServer(
      account: profile,
      token: session.token,
      onProgress: onProgress,
    );
  }

  Future<void> synchronizeFull(
    StoredSession session, {
    SyncProgressCallback? onProgress,
  }) => _sync.synchronizeFull(
    account: session.account,
    token: session.token,
    onProgress: onProgress,
  );

  Future<void> synchronize(
    StoredSession session, {
    SyncProgressCallback? onProgress,
  }) => _sync.synchronize(
    account: session.account,
    token: session.token,
    onProgress: onProgress,
  );

  static Uri normalizeServer(String value) {
    final trimmed = value.trim();
    final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(candidate);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException('invalidServerAddress');
    }
    return uri.replace(
      path: uri.path.endsWith('/') ? uri.path : '${uri.path}/',
    );
  }

  Future<void> requestPasswordReset(String serverAddress, String email) =>
      _api.requestPasswordReset(
        server: normalizeServer(serverAddress),
        email: email.trim(),
      );

  static void _validateCompatibility(LoginResult result) {
    if (_compareVersions(
          Api2Client.clientVersion,
          result.minimumClientVersion,
        ) <
        0) {
      throw const ApiException('clientUpgradeRequired');
    }
    if (_compareVersions(result.serverVersion, Api2Client.clientVersion) < 0) {
      throw const ApiException('serverUpgradeRequired');
    }
  }

  static int _compareVersions(String left, String right) {
    if (right.trim().isEmpty) return 1;
    final a = left.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    final b = right.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    for (var index = 0; index < 3; index++) {
      final av = index < a.length ? a[index] : 0;
      final bv = index < b.length ? b[index] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }
}
