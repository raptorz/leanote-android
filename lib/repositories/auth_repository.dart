import '../core/api/api2_client.dart';
import '../core/api/api_exception.dart';
import '../data/database/app_database.dart';
import '../data/session/session_store.dart';
import '../domain/models/account.dart';
import '../domain/models/note.dart';
import '../domain/models/notebook.dart';
import '../sync/sync_coordinator.dart';

class StoredSession {
  const StoredSession({required this.account, required this.token});

  final Account account;
  final String token;
}

class AuthRepository {
  const AuthRepository(this._api, this._database, this._sessions, this._sync);

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

  Future<StoredSession> loginAndDownload({
    required String serverAddress,
    required String identity,
    required String password,
    SyncProgressCallback? onProgress,
  }) async {
    final server = normalizeServer(serverAddress);
    final result = await _api.login(
      server: server,
      identity: identity.trim(),
      password: password,
    );
    _validateCompatibility(result);
    await _sync.downloadFreshSnapshot(
      account: result.account,
      token: result.token,
      onProgress: onProgress,
    );
    await _sessions.write(result.account.cacheKey, result.token);
    return StoredSession(account: result.account, token: result.token);
  }

  Future<void> logout(StoredSession session) async {
    try {
      await _api.logout(server: session.account.server, token: session.token);
    } on ApiException {
      // Local sign-out must remain available while the server is offline.
    }
    await _sessions.delete(session.account.cacheKey);
    await _database.deactivate(session.account.cacheKey);
  }

  Future<List<Notebook>> notebooks(String accountId) =>
      _database.notebooks(accountId);

  Future<List<Note>> notes(String accountId, {String? notebookId}) =>
      _database.notes(accountId, notebookId: notebookId);

  Future<Note> createNote(
    StoredSession session, {
    required String notebookId,
    required bool isMarkdown,
  }) => _database.createLocalNote(
    account: session.account,
    notebookId: notebookId,
    isMarkdown: isMarkdown,
  );

  Future<void> saveNote(StoredSession session, Note note) =>
      _database.saveLocalNote(session.account.cacheKey, note);

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
