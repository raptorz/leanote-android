import '../core/api/api2_client.dart';
import '../core/api/api_exception.dart';
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
  bool _resetting = false;
  bool _fullSync = false;
  bool _attachmentUploading = false;
  bool get attachmentUploading => _attachmentUploading;

  Future<void> runAttachmentUpload(Future<void> Function() action) {
    if (_running != null) return Future.error(StateError('syncInProgress'));
    _attachmentUploading = true;
    return _running = Future<void>(action).whenComplete(() {
      _running = null;
      _attachmentUploading = false;
    });
  }

  /// Upload dirty notes, then merge all remote rows without clearing local data.
  Future<void> synchronizeFull({
    required Account account,
    required String token,
    SyncProgressCallback? onProgress,
  }) {
    if (_fullSync) return _running!;
    if (_running != null) return Future.error(StateError('syncInProgress'));
    _fullSync = true;
    return _running =
        _synchronize(
          account: account,
          token: token,
          onProgress: onProgress,
          full: true,
        ).whenComplete(() {
          _running = null;
          _fullSync = false;
        });
  }

  Future<void> synchronize({
    required Account account,
    required String token,
    SyncProgressCallback? onProgress,
  }) {
    if (_attachmentUploading) {
      return Future.error(StateError('attachmentUploadInProgress'));
    }
    if (_resetting) return Future.error(StateError('resetInProgress'));
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
    bool full = false,
  }) async {
    final previousUsn = await _database.lastSyncUsn(account.cacheKey);
    final afterUsn = full ? 0 : previousUsn;
    await _uploadChanges(account, token, onProgress);
    // Fix the checkpoint before reading separate resource streams. A change
    // arriving later must remain eligible for the next incremental download.
    final checkpoint = await _api.getSyncUsn(
      server: account.server,
      token: token,
    );
    if (checkpoint < previousUsn) throw StateError('serverSyncStateReset');
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
    onProgress?.call(SyncProgress(SyncStage.saving, notes.length));
    await _database.mergeChanges(
      account: account,
      notebooks: notebooks,
      notes: notes,
      tags: tags,
      lastSyncUsn: checkpoint,
    );
  }

  Future<void> uploadPending({
    required Account account,
    required String token,
    SyncProgressCallback? onProgress,
  }) {
    if (_attachmentUploading) {
      return Future.error(StateError('attachmentUploadInProgress'));
    }
    if (_resetting) return Future.error(StateError('resetInProgress'));
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
      if (local.isDeleted) {
        await _api.deleteTrash(
          server: account.server,
          token: token,
          note: local,
        );
        await _database.acknowledgeDeletion(account.cacheKey, local);
        onProgress?.call(SyncProgress(SyncStage.uploading, index + 1));
        continue;
      }
      try {
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
      } on ApiException catch (error) {
        if (error.code != 'conflict' ||
            error.statusCode != null ||
            local.usn <= 0) {
          rethrow;
        }
        final remote = await _api.getConflictSnapshot(
          server: account.server,
          token: token,
          noteId: local.noteId,
        );
        final copy = await _database.resolveNoteConflict(
          account.cacheKey,
          local,
          remote.note,
          filesConfirmedEmpty: remote.filesConfirmedEmpty,
        );
        if (copy != null) {
          // Persist the copy first. Failed/lost uploads leave this same ID dirty
          // for the next attempt, rather than creating another conflict copy.
          final uploaded = await _api.addNote(
            server: account.server,
            token: token,
            note: copy,
          );
          await _database.markNoteUploaded(account.cacheKey, copy, uploaded);
        }
      }
      onProgress?.call(SyncProgress(SyncStage.uploading, index + 1));
    }
  }

  /// Destructive replacement is invoked only after explicit user confirmation.
  Future<void> resetFromServer({
    required Account account,
    required String token,
    SyncProgressCallback? onProgress,
  }) {
    if (_running != null) return Future.error(StateError('syncInProgress'));
    _resetting = true;
    return _running =
        (() async {
          final expected = await _database.noteSnapshotFingerprint(
            account.cacheKey,
          );
          await _downloadSnapshot(
            account: account,
            token: token,
            onProgress: onProgress,
            expectedNoteSnapshot: expected,
          );
        })().whenComplete(() {
          _running = null;
          _resetting = false;
        });
  }

  Future<void> downloadFreshSnapshot({
    required Account account,
    required String token,
    SyncProgressCallback? onProgress,
  }) {
    if (_running != null) return Future.error(StateError('syncInProgress'));
    return _running = _downloadSnapshot(
      account: account,
      token: token,
      onProgress: onProgress,
    ).whenComplete(() => _running = null);
  }

  Future<void> _downloadSnapshot({
    required Account account,
    required String token,
    SyncProgressCallback? onProgress,
    String? expectedNoteSnapshot,
  }) async {
    final checkpoint = await _api.getSyncUsn(
      server: account.server,
      token: token,
    );
    final notebooks = await _allNotebooks(
      account,
      token,
      onProgress,
      afterUsn: 0,
    );
    final notes = await _allNotes(account, token, onProgress, afterUsn: 0);
    final tags = await _allTags(account, token, onProgress, afterUsn: 0);
    onProgress?.call(SyncProgress(SyncStage.saving, notes.length));
    await _database.replaceSnapshot(
      account: account,
      notebooks: notebooks,
      notes: notes,
      tags: tags,
      lastSyncUsn: checkpoint,
      expectedNoteSnapshot: expectedNoteSnapshot,
    );
  }

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
      if (next <= cursor) throw StateError('notebookSyncCursorStalled');
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
      if (next <= cursor) throw StateError('noteSyncCursorStalled');
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
      if (next <= cursor) throw StateError('tagSyncCursorStalled');
      cursor = next;
    }
    return result;
  }

  static int _integer(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
}
