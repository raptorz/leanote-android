import '../core/api/api2_client.dart';
import '../data/database/app_database.dart';
import '../domain/models/account.dart';
import '../domain/models/note.dart';
import '../domain/models/notebook.dart';

enum SyncStage { notebooks, notes, tags, saving }

class SyncProgress {
  const SyncProgress(this.stage, this.completed);

  final SyncStage stage;
  final int completed;
}

typedef SyncProgressCallback = void Function(SyncProgress progress);

class SyncCoordinator {
  const SyncCoordinator(this._api, this._database);

  final Api2Client _api;
  final AppDatabase _database;

  Future<void> downloadFreshSnapshot({
    required Account account,
    required String token,
    SyncProgressCallback? onProgress,
  }) async {
    final notebooks = await _allNotebooks(account, token, onProgress);
    final notes = await _allNotes(account, token, onProgress);
    final tags = await _allTags(account, token, onProgress);
    final highestUsn = <int>[
      ...notebooks.map((item) => item.usn),
      ...notes.map((item) => item.usn),
      ...tags.map((item) => _integer(item['Usn'])),
    ].fold<int>(0, (highest, value) => value > highest ? value : highest);
    onProgress?.call(SyncProgress(SyncStage.saving, notes.length));
    await _database.replaceSnapshot(
      account: account,
      notebooks: notebooks,
      notes: notes,
      tags: tags,
      lastSyncUsn: highestUsn,
    );
  }

  Future<List<Notebook>> _allNotebooks(
    Account account,
    String token,
    SyncProgressCallback? progress,
  ) async {
    final result = <Notebook>[];
    var cursor = 0;
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
    SyncProgressCallback? progress,
  ) async {
    final result = <Note>[];
    var cursor = 0;
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
    SyncProgressCallback? progress,
  ) async {
    final result = <Map<String, Object?>>[];
    var cursor = 0;
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
