import '../domain/models/note_file.dart';
import 'file_cache_batch.dart';

/// Session-scoped queue: lists are processed one note at a time, with at most
/// three file transfers in flight. Cancellation drains already started work.
class AccountFileCache {
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
}
