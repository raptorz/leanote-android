import 'dart:typed_data';
import 'dart:ui' as ui;

import '../core/api/api2_client.dart';
import '../core/api/api_exception.dart';
import '../data/database/app_database.dart';
import '../data/session/session_store.dart';
import '../domain/models/account.dart';
import '../domain/models/note.dart';
import '../domain/models/note_history.dart';
import '../domain/models/notebook.dart';
import '../domain/models/notebook_tree.dart';
import '../sync/sync_coordinator.dart';

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

  Future<void> refreshAccountPresentation(StoredSession session) {
    final key = session.account.cacheKey;
    return _presentationRefreshes[key] ??= (() async {
      final profile = await refreshProfile(session);
      await refreshAvatar(session, profile);
    })().whenComplete(() {
      _presentationRefreshes.remove(key);
    });
  }

  final Api2Client _api;
  final AppDatabase _database;
  final SessionStore _sessions;
  final SyncCoordinator _sync;

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
  }

  Future<void> prepareLogout(
    StoredSession session, {
    SyncProgressCallback? onProgress,
  }) async {
    if ((await pendingNoteIds(session.account.cacheKey)).isEmpty) return;
    await _sync.uploadPending(
      account: session.account,
      token: session.token,
      onProgress: onProgress,
    );
    if ((await pendingNoteIds(session.account.cacheKey)).isNotEmpty) {
      throw StateError('unsyncedChanges');
    }
  }

  Future<void> logout(
    StoredSession session, {
    bool discardSessionWithPendingChanges = false,
  }) async {
    if (!discardSessionWithPendingChanges &&
        (await pendingNoteIds(session.account.cacheKey)).isNotEmpty) {
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

  Future<void> saveNotebook(
    StoredSession session, {
    required String title,
    Notebook? existing,
    String? parentNotebookId,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) throw const FormatException('请输入笔记本名称');
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

  Future<List<Note>> notesForTag(String accountId, String tag) =>
      _database.notesForTag(accountId, tag);

  Future<Set<String>> pendingNoteIds(String accountId) =>
      _database.pendingNoteIds(accountId);

  Future<List<Note>> searchNotes(
    String accountId,
    String query, {
    int limit = 50,
  }) => _database.searchNotes(accountId, query, limit: limit);

  Future<Note> createNote(
    StoredSession session, {
    required String notebookId,
    required bool isMarkdown,
  }) => _database.createLocalNote(
    account: session.account,
    notebookId: notebookId,
    isMarkdown: isMarkdown,
  );

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
