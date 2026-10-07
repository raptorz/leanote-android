import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gemsnote/data/database/app_database.dart';
import 'package:gemsnote/domain/models/account.dart';
import 'package:gemsnote/repositories/auth_repository.dart';
import 'package:gemsnote/services/note_image_picker.dart';
import 'package:gemsnote/sync/sync_coordinator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'attachment_upload_repository_test.dart'
    show UploadApi, original, noteId;
import 'cached_login_test.dart' show MemorySessions;

const reference = '/api2/file/getImage?fileId=507f1f77bcf86cd799439012';

class ImageApi extends UploadApi {
  @override
  Future<String> uploadNoteImage({
    required Uri server,
    required String token,
    required String userId,
    required String identity,
    required String password,
    required String noteId,
    required NoteImageUpload image,
  }) async {
    uploads++;
    await duringUpload?.call();
    return reference;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late ImageApi api;
  late AuthRepository repo;
  late SyncCoordinator sync;
  late StoredSession session;
  late NoteImageUpload image;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await AppDatabase.open(databasePath: inMemoryDatabasePath);
    session = StoredSession(
      account: Account(
        userId: 'u',
        server: Uri.parse('https://example.com'),
        username: 'user',
        email: '',
        logo: '',
      ),
      token: 't',
    );
    await db.replaceSnapshot(
      account: session.account,
      notebooks: [],
      notes: [original],
      tags: [],
      lastSyncUsn: 5,
    );
    api = ImageApi();
    sync = SyncCoordinator(api, db);
    repo = AuthRepository(api, db, MemorySessions(), sync);
    image = await NoteImageUpload.normalize(
      File('assets/images/gemsnote_s.png').readAsBytesSync(),
    );
  });
  tearDown(() => db.raw.close());
  Future<String> upload([String id = noteId]) =>
      repo.uploadNoteImage(session, id, image, identity: 'user', password: 'p');

  test('dirty draft uploads first, then inserted reference persists locally and syncs', () async {
    await db.saveEditedText(session.account.cacheKey, noteId, 'Title', 'draft');
    final other = await db.createLocalNote(
      account: session.account,
      notebookId: '',
      isMarkdown: true,
    );
    expect(await upload(), reference);
    expect(api.noteWrites, ['update:$noteId']);
    expect(await db.pendingNoteIds(session.account.cacheKey), {other.noteId});
    await db.saveEditedText(
      session.account.cacheKey,
      noteId,
      'Title',
      'draft\n![]($reference)',
    );
    expect(await db.pendingNoteIds(session.account.cacheKey), contains(noteId));
    expect(
      (await db.notes(session.account.cacheKey))
          .firstWhere((n) => n.noteId == noteId)
          .content,
      contains(reference),
    );
    await sync.runAttachmentUpload(
      () async {},
      account: session.account,
      token: 't',
      noteId: noteId,
    );
    expect(api.remote.content, contains(reference));
    expect(api.uploads, 1);
    expect(await db.pendingNoteIds(session.account.cacheKey), {other.noteId});
    expect(await db.lastSyncUsn(session.account.cacheKey), 5);
  });
  test('new note is created before image upload', () async {
    final note = await db.createLocalNote(
      account: session.account,
      notebookId: '',
      isMarkdown: true,
    );
    expect(await upload(note.noteId), reference);
    expect(api.noteWrites, ['add:${note.noteId}']);
    expect(api.uploads, 1);
  });
  test('body conflict and concurrent edits block image upload and retain dirty draft', () async {
    await db.saveEditedText(session.account.cacheKey, noteId, 'Title', 'draft');
    api.failNoteSave = true;
    await expectLater(upload(), throwsStateError);
    expect(api.uploads, 0);
    api.failNoteSave = false;
    api.duringNoteSave = () =>
        db.saveEditedText(session.account.cacheKey, noteId, 'Title', 'newer');
    await expectLater(upload(), throwsStateError);
    expect(api.uploads, 0);
    expect((await db.notes(session.account.cacheKey)).single.content, 'newer');
    expect(await db.pendingNoteIds(session.account.cacheKey), {noteId});
  });
  test(
    'image upload excludes sync, reset, logout and duplicate uploads',
    () async {
      final gate = Completer<void>();
      final started = Completer<void>();
      api.duringUpload = () {
        started.complete();
        return gate.future;
      };
      final pending = upload();
      await started.future;
      try {
        await expectLater(
          sync.synchronize(account: session.account, token: 't'),
          throwsStateError,
        );
        await expectLater(
          sync.resetFromServer(account: session.account, token: 't'),
          throwsStateError,
        );
        await expectLater(
          repo.logout(session, discardSessionWithPendingChanges: true),
          throwsStateError,
        );
        await expectLater(upload(), throwsStateError);
      } finally {
        gate.complete();
      }
      expect(await pending, reference);
      expect(api.uploads, 1);
      expect(sync.attachmentUploading, false);
    },
  );
  test('unknown and foreign notes are rejected locally', () async {
    await expectLater(upload('missing'), throwsStateError);
    await db.raw.update('notes', {'owner_server_id': 'other'});
    await expectLater(upload(), throwsStateError);
    expect(api.uploads, 0);
  });
}
