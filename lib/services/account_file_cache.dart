import '../domain/models/note_file.dart';
import '../data/database/file_download_journal.dart';
import 'file_cache_batch.dart';

/// Lists are processed one note at a time, with at most three file transfers in
/// flight. The optional journal retains progress across sessions. Cancellation
/// drains already started work.
class AccountFileCache {
  AccountFileCache({this.journal});
  final FileDownloadJournal? journal;
  bool _cancelled = false;
  bool _started = false;
  bool get cancelled => _cancelled;
  FileCacheBatch? _batch;
  void cancel() {
    _cancelled = true;
    _batch?.cancel();
  }

  Future<void> run(
    List<String> noteIds, {
    required Future<List<NoteFile>> Function(String) listFiles,
    required Future<void> Function(String, NoteFile) download,
    required void Function(int notes, int files, int failures) onProgress,
  }) async {
    if (_started) throw StateError('queueAlreadyStarted');
    _started = true;
    final journal = this.journal;
    if (journal != null) {
      await _runPersistent(journal, noteIds, listFiles, download, onProgress);
      return;
    }
    var notes = 0;
    var files = 0;
    var failures = 0;
    for (final id in noteIds.toSet()) {
      if (_cancelled) break;
      try {
        final items = await listFiles(id);
        if (_cancelled) break;
        final batch = _batch = FileCacheBatch();
        final result = await batch.run(
          items,
          download: (file) => download(id, file),
          onProgress: (p) =>
              onProgress(notes, files + p.completed, failures + p.failed),
        );
        files += result.completed;
        failures += result.failed.length;
      } on Object {
        failures++;
      } finally {
        _batch = null;
      }
      notes++;
      onProgress(notes, files, failures);
    }
  }

  Future<void> _runPersistent(
    FileDownloadJournal journal,
    List<String> noteIds,
    Future<List<NoteFile>> Function(String) listFiles,
    Future<void> Function(String, NoteFile) download,
    void Function(int, int, int) onProgress,
  ) async {
    if (_cancelled) return;
    final jobs = await journal.plan(noteIds);
    var notes = 0, files = 0, failures = 0;
    for (final job in jobs) {
      if (_cancelled) break;
      try {
        var entries = await journal.entries(job);
        if (_cancelled) break;
        if (entries == null) {
          final listed = await listFiles(job.noteId);
          // Persist the listing even on pause so resume need not invalidate
          // successful cache writes by refreshing the list again.
          await journal.saveList(job, listed);
          entries = listed.map((file) => DownloadEntry(file, false)).toList();
        }
        if (_cancelled) break;
        final pending = entries
            .where((entry) => !entry.done)
            .map((entry) => entry.file)
            .toList();
        final batch = _batch = FileCacheBatch();
        final result = await batch.run(
          pending,
          download: (file) async {
            try {
              if (!await journal.hasCachedBytes(job, file)) {
                await download(job.noteId, file);
              }
              await journal.finishFile(job, file, success: true);
            } on Object {
              await journal.finishFile(job, file, success: false);
              rethrow;
            }
          },
          onProgress: (progress) => onProgress(
            notes,
            files + progress.completed,
            failures + progress.failed,
          ),
        );
        files += result.completed;
        failures += result.failed.length;
      } on Object {
        failures++;
        await journal.failList(job);
      } finally {
        _batch = null;
      }
      notes++;
      onProgress(notes, files, failures);
    }
  }
}
