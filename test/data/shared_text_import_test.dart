import 'package:flutter_test/flutter_test.dart';
import 'package:gemsnote/core/api/api2_client.dart';
import 'package:gemsnote/data/database/app_database.dart';
import 'package:gemsnote/domain/models/account.dart';
import 'package:gemsnote/domain/models/notebook.dart';
import 'package:gemsnote/repositories/auth_repository.dart';
import 'package:gemsnote/services/shared_text_inbox.dart';
import 'package:gemsnote/sync/sync_coordinator.dart';
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'cached_login_test.dart' show MemorySessions;

void main() {
  late AppDatabase db;
  late AuthRepository repo;
  late StoredSession session;
  final source = SharedText(
    id: '507f1f77bcf86cd799439012',
    title: 'Title',
    text: 'Text https://example.test',
  );
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await AppDatabase.open(databasePath: inMemoryDatabasePath);
    session = StoredSession(
      account: Account(
        userId: 'u',
        server: Uri.parse('https://example.test'),
        username: 'u',
        email: '',
        logo: '',
      ),
      token: 't',
    );
    await db.replaceSnapshot(
      account: session.account,
      notebooks: [
        Notebook.fromJson({'NotebookId': 'book', 'Title': 'Book'}),
      ],
      notes: [],
      tags: [],
      lastSyncUsn: 2,
    );
    final api = Api2Client(
      httpClient: MockClient(
        (_) async => throw StateError('must stay offline'),
      ),
    );
    repo = AuthRepository(api, db, MemorySessions(), SyncCoordinator(api, db));
  });
  tearDown(() => db.raw.close());
  test(
    'import creates dirty Markdown with stable ID and complete source offline',
    () async {
      final note = await repo.importSharedText(session, source, 'book');
      expect(note.noteId, source.id);
      expect(note.content, source.text);
      expect(note.isMarkdown, true);
      expect(note.notebookId, 'book');
      expect(note.usn, 0);
      expect(await db.pendingNoteIds(session.account.cacheKey), {source.id});
      expect(await db.lastSyncUsn(session.account.cacheKey), 2);
    },
  );
  test(
    'acknowledgement retry does not duplicate or overwrite later edits',
    () async {
      await repo.importSharedText(session, source, 'book');
      await db.saveEditedText(
        session.account.cacheKey,
        source.id,
        'Changed',
        'New body',
      );
      final again = await repo.importSharedText(session, source, 'book');
      expect(again.title, 'Changed');
      expect(again.content, 'New body');
      expect((await db.notes(session.account.cacheKey)).length, 1);
    },
  );
  test(
    'missing notebook and foreign account claim do not write a note',
    () async {
      await expectLater(
        repo.importSharedText(session, source, 'gone'),
        throwsStateError,
      );
      final claimed = SharedText(
        id: source.id,
        title: source.title,
        text: source.text,
        accountKey: 'other',
      );
      await expectLater(
        Future.sync(() => repo.importSharedText(session, claimed, 'book')),
        throwsStateError,
      );
      expect(await db.notes(session.account.cacheKey), isEmpty);
    },
  );
}
