import '../core/api/api2_client.dart';
import '../data/database/app_database.dart';
import '../domain/models/account.dart';
import '../domain/models/note.dart';
import '../domain/models/notebook.dart';

enum SyncStage { uploading, notebooks, notes, tags, saving }

class SyncProgress {
  const SyncProgress(this.stage, this.completed);

  final SyncStage stage;
  final int completed;
}

typedef SyncProgressCallback = void Function(SyncProgress progress);

class SyncCoordinator {
  SyncCoordinator(this._api, this._database);

  final Api2Client _api;
  final AppDatabase _database;
  Future<void>? _running;
  bool _uploadingOnly = false;

  Future<void> synchronize({
    required Account account,
    required String token,
    SyncProgressCallback? onProgress,
  }) {
    if (_uploadingOnly) {
      return _running!.then(
        (_) =>
            synchronize(account: account, token: token, onProgress: onProgress),
      );
    }
    return _running ??= _synchronize(
      account: account,
      token: token,
      onProgress: onProgress,
    ).whenComplete(() => _running = null);
  }

  Future<void> _synchronize({
    required Account account,
    required String token,
    SyncProgressCallback? onProgress,
  }) async {
    final afterUsn = await _database.lastSyncUsn(account.cacheKey);
    await _uploadChanges(account, token, onProgress);
    final notebooks = await _allNotebooks(
      account,
      token,
      onProgress,
      afterUsn: afterUsn,
    );
    final notes = await _allNotes(
      account,
      token,
      onProgress,
      afterUsn: afterUsn,
    );
    final tags = await _allTags(account, token, onProgress, afterUsn: afterUsn);
    final highestUsn = _highestUsn(afterUsn, notebooks, notes, tags);
    onProgress?.call(SyncProgress(SyncStage.saving, notes.length));
    await _database.mergeChanges(
      account: account,
      notebooks: notebooks,
      notes: notes,
      tags: tags,
      lastSyncUsn: highestUsn,
    );
  }

  Future<void> uploadPending({
    required Account account,
    required String token,
    SyncProgressCallback? onProgress,
  }) {
    if (_running != null) return _running!;
    _uploadingOnly = true;
    return _running = _uploadChanges(account, token, onProgress).whenComplete(
      () {
        _running = null;
        _uploadingOnly = false;
      },
    );
  }

  Future<void> _uploadChanges(
    Account account,
    String token,
    SyncProgressCallback? onProgress,
  ) async {
    final dirty = await _database.dirtyNotes(account.cacheKey);
    onProgress?.call(SyncProgress(SyncStage.uploading, 0));
    for (var index = 0; index < dirty.length; index++) {
      final local = dirty[index];
      final remote = local.usn == 0
          ? await _api.addNote(
              server: account.server,
              token: token,
              note: local,
            )
          : await _api.updateNote(
              server: account.server,
              token: token,
              note: local,
            );
      await _database.markNoteUploaded(account.cacheKey, local, remote);
      onProgress?.call(SyncProgress(SyncStage.uploading, index + 1));
    }
  }

  Future<void> downloadFreshSnapshot({
    required Account account,
    required String token,
    SyncProgressCallback? onProgress,
  }) async {
    final notebooks = await _allNotebooks(
      account,
      token,
      onProgress,
      afterUsn: 0,
    );
    final notes = await _allNotes(account, token, onProgress, afterUsn: 0);
    final tags = await _allTags(account, token, onProgress, afterUsn: 0);
    final highestUsn = _highestUsn(0, notebooks, notes, tags);
    onProgress?.call(SyncProgress(SyncStage.saving, notes.length));
    await _database.replaceSnapshot(
      account: account,
      notebooks: notebooks,
      notes: notes,
      tags: tags,
      lastSyncUsn: highestUsn,
    );
  }

  static int _highestUsn(
    int initial,
    List<Notebook> notebooks,
    List<Note> notes,
    List<Map<String, Object?>> tags,
  ) => <int>[
    initial,
    ...notebooks.map((item) => item.usn),
    ...notes.map((item) => item.usn),
    ...tags.map((item) => _integer(item['Usn'])),
  ].fold<int>(0, (highest, value) => value > highest ? value : highest);

  Future<List<Notebook>> _allNotebooks(
    Account account,
    String token,
    SyncProgressCallback? progress, {
    required int afterUsn,
  }) async {
    final result = <Notebook>[];
    progress?.call(SyncProgress(SyncStage.notebooks, 0));
    var cursor = afterUsn;
    while (true) {
      final page = await _api.getNotebooks(
        server: account.server,
        token: token,
        afterUsn: cursor,
      );
      result.addAll(page);
      progress?.call(SyncProgress(SyncStage.notebooks, result.length));
      if (page.isEmpty || page.length < 100) break;
      final next = page.fold<int>(
        cursor,
        (usn, item) => item.usn > usn ? item.usn : usn,
      );
      if (next <= cursor) break;
      cursor = next;
    }
    return result;
  }

  Future<List<Note>> _allNotes(
    Account account,
    String token,
    SyncProgressCallback? progress, {
    required int afterUsn,
  }) async {
    final result = <Note>[];
    progress?.call(SyncProgress(SyncStage.notes, 0));
    var cursor = afterUsn;
    while (true) {
      final page = await _api.getNotesWithContent(
        server: account.server,
        token: token,
        afterUsn: cursor,
      );
      result.addAll(page);
      progress?.call(SyncProgress(SyncStage.notes, result.length));
      if (page.isEmpty || page.length < 50) break;
      final next = page.fold<int>(
        cursor,
        (usn, item) => item.usn > usn ? item.usn : usn,
      );
      if (next <= cursor) break;
      cursor = next;
    }
    return result;
  }

  Future<List<Map<String, Object?>>> _allTags(
    Account account,
    String token,
    SyncProgressCallback? progress, {
    required int afterUsn,
  }) async {
    final result = <Map<String, Object?>>[];
    progress?.call(SyncProgress(SyncStage.tags, 0));
    var cursor = afterUsn;
    while (true) {
      final page = await _api.getTags(
        server: account.server,
        token: token,
        afterUsn: cursor,
      );
      result.addAll(page);
      progress?.call(SyncProgress(SyncStage.tags, result.length));
      if (page.isEmpty || page.length < 100) break;
      final next = page.fold<int>(cursor, (usn, item) {
        final value = _integer(item['Usn']);
        return value > usn ? value : usn;
      });
      if (next <= cursor) break;
      cursor = next;
    }
    return result;
  }

  static int _integer(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
}
