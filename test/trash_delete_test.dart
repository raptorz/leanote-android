import 'package:flutter_test/flutter_test.dart';
import 'package:gemsnote/core/api/api2_client.dart';
import 'package:gemsnote/core/api/api_exception.dart';
import 'package:gemsnote/data/database/app_database.dart';
import 'package:gemsnote/domain/models/account.dart';
import 'package:gemsnote/domain/models/note.dart';
import 'package:gemsnote/sync/sync_coordinator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final account = Account(
    userId: 'u',
    server: Uri.parse('https://notes.example.test/'),
    username: 'u',
    email: '',
    logo: '',
  );
  final note = Note.fromJson({
    'NoteId': '507f1f77bcf86cd799439011',
    'Title': 'Trash',
    'Content': 'Keep until acknowledged',
    'IsTrash': true,
    'Usn': 5,
  });
  late AppDatabase db;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    db = await AppDatabase.open(databasePath: inMemoryDatabasePath);
    await db.replaceSnapshot(
      account: account,
      notebooks: [],
      notes: [note],
      tags: [],
      lastSyncUsn: 5,
    );
  });
  tearDown(() => db.raw.close());

  test('queued deletion stays dirty, hidden, and cannot be resurrected by stale edits', () async {
    await db.deleteLocalTrash(account.cacheKey, note.noteId);
    expect(await db.notes(account.cacheKey, trashOnly: true), isEmpty);
    expect((await db.dirtyNotes(account.cacheKey)).single.isDeleted, isTrue);
    expect(
      (await db.dirtyNotes(account.cacheKey)).single.content,
      note.content,
    );
    await expectLater(
      db.saveLocalNote(account.cacheKey, note),
      throwsStateError,
    );
    await expectLater(
      db.saveEditedText(account.cacheKey, note.noteId, '', ''),
      throwsStateError,
    );
    // An upload already in flight must not acknowledge a later deletion.
    await db.markNoteUploaded(account.cacheKey, note, note.copyWith(usn: 6));
    expect((await db.dirtyNotes(account.cacheKey)).single.usn, 6);
    expect((await db.dirtyNotes(account.cacheKey)).single.isDeleted, isTrue);
    await expectLater(
      db.mergeChanges(
        account: account,
        notebooks: [],
        notes: [note],
        tags: [],
        lastSyncUsn: 6,
      ),
      throwsStateError,
    );
    expect(await db.lastSyncUsn(account.cacheKey), 5);
  });

  test('delete requires current-account trash item', () async {
    await expectLater(
      db.deleteLocalTrash('another-account', note.noteId),
      throwsStateError,
    );
    await db.saveLocalNote(account.cacheKey, note.copyWith(isTrash: false));
    await expectLater(
      db.deleteLocalTrash(account.cacheKey, note.noteId),
      throwsStateError,
    );
    expect((await db.notes(account.cacheKey)).single.noteId, note.noteId);
  });

  for (final response in [
    '{"Ok":true,"Usn":6}',
    '{"Ok":false,"Msg":"notExists"}',
    '{"Ok":false,"Msg":"conflict"}',
    '{"Ok":true}',
    '{}',
  ]) {
    test('delete response $response', () async {
      await db.deleteLocalTrash(account.cacheKey, note.noteId);
      final api = Api2Client(
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api2/client/note/deleteTrash');
          expect(request.bodyFields, {'noteId': note.noteId, 'usn': '5'});
          return http.Response(response, 200);
        }),
      );
      final sync = SyncCoordinator(api, db);
      final operation = sync.uploadPending(
        account: account,
        token: 'test-token',
      );
      if (response.contains('conflict') ||
          response == '{}' ||
          response == '{"Ok":true}') {
        await expectLater(operation, throwsA(isA<ApiException>()));
        expect(await db.pendingNoteIds(account.cacheKey), {note.noteId});
      } else {
        await operation;
        expect(await db.pendingNoteIds(account.cacheKey), isEmpty);
        expect(await db.raw.query('notes'), isEmpty);
      }
      expect(await db.lastSyncUsn(account.cacheKey), 5);
    });
  }

  for (final exists in [false, true]) {
    test('unconfirmed new note checks remote existence: $exists', () async {
      final draft = await db.createLocalNote(
        account: account,
        notebookId: 'book',
        isMarkdown: true,
      );
      await db.saveLocalNote(account.cacheKey, draft.copyWith(isTrash: true));
      await db.deleteLocalTrash(account.cacheKey, draft.noteId);
      final api = Api2Client(
        httpClient: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api2/note/getNote');
          expect(request.url.queryParameters['noteId'], draft.noteId);
          return http.Response(
            exists
                ? '{"NoteId":"${draft.noteId}","Usn":8}'
                : '{"Ok":false,"Msg":"notExists"}',
            200,
          );
        }),
      );
      final operation = SyncCoordinator(
        api,
        db,
      ).uploadPending(account: account, token: 'test-token');
      if (exists) {
        await expectLater(operation, throwsA(isA<ApiException>()));
        expect(await db.pendingNoteIds(account.cacheKey), {draft.noteId});
      } else {
        await operation;
        expect(await db.pendingNoteIds(account.cacheKey), isEmpty);
      }
    });
  }
}
