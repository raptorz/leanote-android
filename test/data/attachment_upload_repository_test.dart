import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gemsnote/core/api/api2_client.dart';
import 'package:gemsnote/data/database/app_database.dart';
import 'package:gemsnote/domain/models/account.dart';
import 'package:gemsnote/domain/models/attachment_upload.dart';
import 'package:gemsnote/domain/models/note.dart';
import 'package:gemsnote/domain/models/note_file.dart';
import 'package:gemsnote/repositories/auth_repository.dart';
import 'package:gemsnote/sync/sync_coordinator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'cached_login_test.dart' show MemorySessions;

const noteId = '507f1f77bcf86cd799439011';
const fileId = '507f1f77bcf86cd799439012';
final original = Note.fromJson({
  'NoteId': noteId,
  'UserId': 'u',
  'Usn': 5,
  'Content': 'body',
});

class UploadApi extends Api2Client {
  int uploads = 0;
  bool failRefresh = false;
  Future<void> Function()? duringUpload;
  @override
  Future<String> uploadAttachment({
    required Uri server,
    required String token,
    required String userId,
    required String identity,
    required String password,
    required String noteId,
    required AttachmentUpload file,
  }) async {
    uploads++;
    await duringUpload?.call();
    return fileId;
  }

  @override
  Future<({Note note, bool filesConfirmedEmpty})> getConflictSnapshot({
    required Uri server,
    required String token,
    required String noteId,
  }) async {
    if (failRefresh) throw StateError('offline');
    return (note: original.copyWith(usn: 6), filesConfirmedEmpty: false);
  }

  @override
  Future<List<NoteFile>> noteFiles({
    required Uri server,
    required String token,
    required String noteId,
    required String userId,
  }) async => [
    const NoteFile(id: fileId, title: 'a.txt', type: 'txt', isAttachment: true),
  ];
}

void main() {
  late AppDatabase db;
  late UploadApi api;
  late AuthRepository repo;
  late SyncCoordinator sync;
  late StoredSession session;
  final file = AttachmentUpload(name: 'a.txt', bytes: Uint8List.fromList([1]));
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
    api = UploadApi();
    sync = SyncCoordinator(api, db);
    repo = AuthRepository(api, db, MemorySessions(), sync);
  });
  tearDown(() => db.raw.close());
  Future<bool> upload() => repo.uploadAttachment(
    session,
    noteId,
    file,
    identity: 'u',
    password: 'p',
  );
  test(
    'upload refreshes note USN and files without skipping sync cursor',
    () async {
      expect(await upload(), isTrue);
      expect((await db.notes(session.account.cacheKey)).single.usn, 6);
      expect(await db.lastSyncUsn(session.account.cacheKey), 5);
      expect(
        (await db.cachedNoteFiles(session.account.cacheKey, noteId)).single.id,
        fileId,
      );
    },
  );
  test(
    'refresh failure reports confirmed upload separately and does not retry',
    () async {
      api.failRefresh = true;
      expect(await upload(), isFalse);
      expect(api.uploads, 1);
      expect(sync.attachmentUploading, isFalse);
    },
  );
  test('dirty note is rejected before remote upload', () async {
    await db.saveLocalNote(
      session.account.cacheKey,
      original.copyWith(content: 'draft'),
    );
    await expectLater(upload(), throwsStateError);
    expect(api.uploads, 0);
    expect(sync.attachmentUploading, isFalse);
  });
  test('edits during upload are preserved when refresh cannot merge', () async {
    api.duringUpload = () => db.saveLocalNote(
      session.account.cacheKey,
      original.copyWith(content: 'new edit'),
    );
    expect(await upload(), isFalse);
    expect(
      (await db.notes(session.account.cacheKey)).single.content,
      'new edit',
    );
    expect(await db.pendingNoteIds(session.account.cacheKey), contains(noteId));
  });
  test('upload excludes sync, reset, duplicate upload and logout', () async {
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
        sync.synchronizeFull(account: session.account, token: 't'),
        throwsStateError,
      );
      await expectLater(
        sync.resetFromServer(account: session.account, token: 't'),
        throwsStateError,
      );
      await expectLater(
        sync.downloadFreshSnapshot(account: session.account, token: 't'),
        throwsStateError,
      );
      await expectLater(
        sync.uploadPending(account: session.account, token: 't'),
        throwsStateError,
      );
      await expectLater(upload(), throwsStateError);
      await expectLater(
        repo.logout(session, discardSessionWithPendingChanges: true),
        throwsStateError,
      );
    } finally {
      gate.complete();
    }
    expect(await pending, isTrue);
    expect(api.uploads, 1);
  });
}
