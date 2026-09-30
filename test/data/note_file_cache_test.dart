import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gemsnote/core/api/api2_client.dart';
import 'package:gemsnote/repositories/auth_repository.dart';
import 'package:gemsnote/sync/sync_coordinator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'cached_login_test.dart' show MemorySessions;

import 'package:gemsnote/data/database/app_database.dart';
import 'package:gemsnote/domain/models/account.dart';
import 'package:gemsnote/domain/models/note.dart';
import 'package:gemsnote/domain/models/note_file.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final account = Account(
    userId: 'u',
    server: Uri.parse('https://example.test'),
    username: 'u',
    email: '',
    logo: '',
  );
  const file = NoteFile(
    id: 'f',
    title: 'photo',
    type: 'png',
    isAttachment: false,
  );
  late AppDatabase db;
  Future<void> seed(AppDatabase target) => target.replaceSnapshot(
    account: account,
    notebooks: [],
    notes: [
      Note.fromJson({'NoteId': 'n', 'UserId': 'u'}),
    ],
    tags: [],
    lastSyncUsn: 1,
  );
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    db = await AppDatabase.open(databasePath: inMemoryDatabasePath);
    await seed(db);
  });
  tearDown(() => db.raw.close());
  test('inline image cache requires current account, note and image membership without network', () async {
    const id = '507f1f77bcf86cd799439011';
    const image = NoteFile(
      id: id,
      title: 'photo',
      type: 'png',
      isAttachment: false,
    );
    await db.replaceNoteFiles(account.cacheKey, 'n', [image]);
    final current = (await db.cachedNoteFiles(account.cacheKey, 'n')).single;
    await db.cacheNoteImage(
      account.cacheKey,
      'n',
      current,
      Uint8List.fromList([1]),
    );
    var calls = 0;
    final api = Api2Client(
      httpClient: MockClient((_) async {
        calls++;
        throw StateError('must not request network');
      }),
    );
    final repo = AuthRepository(
      api,
      db,
      MemorySessions(),
      SyncCoordinator(api, db),
    );
    final session = StoredSession(account: account, token: 'test');
    final uri = Uri.parse('/api2/file/getImage?fileId=$id');
    expect(await repo.cachedInlineImage(session, 'n', uri), [1]);
    expect(await repo.cachedInlineImage(session, 'other', uri), isNull);
    expect(
      await repo.cachedInlineImage(
        session,
        'n',
        Uri.parse('https://other.test$uri'),
      ),
      isNull,
    );
    await db.replaceNoteFiles(account.cacheKey, 'n', [
      const NoteFile(
        id: id,
        title: 'attachment',
        type: 'png',
        isAttachment: true,
      ),
    ]);
    expect(await repo.cachedInlineImage(session, 'n', uri), isNull);
    expect(calls, 0);
  });
  test('repository offline reads never call network; failures do not silently fall back', () async {
    await db.replaceNoteFiles(account.cacheKey, 'n', [file]);
    final current = (await db.cachedNoteFiles(account.cacheKey, 'n')).single;
    await db.cacheNoteImage(
      account.cacheKey,
      'n',
      current,
      Uint8List.fromList([1]),
    );
    var calls = 0;
    var denied = false;
    final api = Api2Client(
      httpClient: MockClient((_) async {
        calls++;
        if (!denied) throw Exception('offline');
        return http.Response('{"Ok":false,"Msg":"noPermission"}', 200);
      }),
    );
    final repo = AuthRepository(
      api,
      db,
      MemorySessions(),
      SyncCoordinator(api, db),
    );
    final session = StoredSession(account: account, token: 'test');
    expect(await repo.noteFiles(session, 'n', cachedOnly: true), hasLength(1));
    expect(await repo.noteImage(session, 'n', current, cachedOnly: true), [1]);
    expect(calls, 0);
    await expectLater(repo.noteImage(session, 'n', current), throwsException);
    expect(await repo.noteImage(session, 'n', current, cachedOnly: true), [1]);
    denied = true;
    await expectLater(repo.noteImage(session, 'n', current), throwsException);
    expect(await repo.noteFiles(session, 'n', cachedOnly: true), isEmpty);
    expect(calls, 2);
  });
  test('account/note isolation, logout retention and reset cleanup', () async {
    await db.replaceNoteFiles(account.cacheKey, 'n', [file]);
    final current = (await db.cachedNoteFiles(account.cacheKey, 'n')).single;
    await expectLater(
      db.cachedNoteImage(account.cacheKey, 'n', current),
      throwsStateError,
    );
    await db.cacheNoteImage(
      account.cacheKey,
      'n',
      current,
      Uint8List.fromList([1, 2]),
    );
    expect(await db.cachedNoteImage(account.cacheKey, 'n', current), [1, 2]);
    expect(await db.cachedNoteFiles('other', 'n'), isEmpty);
    await expectLater(
      db.cachedNoteImage(account.cacheKey, 'other', current),
      throwsStateError,
    );
    expect(await db.dirtyNotes(account.cacheKey), isEmpty);
    await db.deactivate(account.cacheKey);
    expect(await db.cachedNoteImage(account.cacheKey, 'n', current), [1, 2]);
    await seed(db);
    expect(await db.cachedNoteFiles(account.cacheKey, 'n'), isEmpty);
  });
  test(
    'refresh invalidates bytes and rejects late download even for same file ID',
    () async {
      await db.replaceNoteFiles(account.cacheKey, 'n', [file]);
      final old = (await db.cachedNoteFiles(account.cacheKey, 'n')).single;
      await db.cacheNoteImage(
        account.cacheKey,
        'n',
        old,
        Uint8List.fromList([1]),
      );
      await db.replaceNoteFiles(account.cacheKey, 'n', [file]);
      final current = (await db.cachedNoteFiles(account.cacheKey, 'n')).single;
      expect(current.cacheGeneration, isNot(old.cacheGeneration));
      await expectLater(
        db.cachedNoteImage(account.cacheKey, 'n', current),
        throwsStateError,
      );
      await expectLater(
        db.cacheNoteImage(account.cacheKey, 'n', old, Uint8List.fromList([2])),
        throwsStateError,
      );
      await db.replaceNoteFiles(account.cacheKey, 'n', []);
      await expectLater(
        db.cacheNoteImage(
          account.cacheKey,
          'n',
          current,
          Uint8List.fromList([2]),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'failed list transaction retains cache, deleting note cascades',
    () async {
      await db.replaceNoteFiles(account.cacheKey, 'n', [file]);
      final current = (await db.cachedNoteFiles(account.cacheKey, 'n')).single;
      await db.cacheNoteImage(
        account.cacheKey,
        'n',
        current,
        Uint8List.fromList([1]),
      );
      await expectLater(
        db.replaceNoteFiles(account.cacheKey, 'n', [file, file]),
        throwsA(isA<DatabaseException>()),
      );
      expect(await db.cachedNoteImage(account.cacheKey, 'n', current), [1]);
      await db.raw.delete(
        'notes',
        where: 'account_id = ?',
        whereArgs: [account.cacheKey],
      );
      expect(await db.cachedNoteFiles(account.cacheKey, 'n'), isEmpty);
    },
  );
  test(
    '64 MiB budget evicts oldest image bytes but retains file entries',
    () async {
      final files = List.generate(
        9,
        (i) =>
            NoteFile(id: '$i', title: '$i', type: 'png', isAttachment: false),
      );
      await db.replaceNoteFiles(account.cacheKey, 'n', files);
      final current = await db.cachedNoteFiles(account.cacheKey, 'n');
      final bytes = Uint8List(8 * 1024 * 1024);
      for (final item in current) {
        await db.cacheNoteImage(account.cacheKey, 'n', item, bytes);
      }
      await expectLater(
        db.cachedNoteImage(account.cacheKey, 'n', current.first),
        throwsStateError,
      );
      expect(
        (await db.cachedNoteImage(account.cacheKey, 'n', current.last)).length,
        bytes.length,
      );
      expect(await db.cachedNoteFiles(account.cacheKey, 'n'), hasLength(9));
    },
  );
  test('v4 upgrade preserves notes and stores cache across reopen', () async {
    final dir = await Directory.systemTemp.createTemp('gemsnote-file-cache-');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/db.sqlite';
    final old = await AppDatabase.open(databasePath: path);
    await seed(old);
    await old.raw.execute('DROP TABLE note_files');
    await old.raw.setVersion(4);
    await old.raw.close();
    final migrated = await AppDatabase.open(databasePath: path);
    expect(await migrated.notes(account.cacheKey), hasLength(1));
    await migrated.replaceNoteFiles(account.cacheKey, 'n', [file]);
    final current = (await migrated.cachedNoteFiles(
      account.cacheKey,
      'n',
    )).single;
    await migrated.cacheNoteImage(
      account.cacheKey,
      'n',
      current,
      Uint8List.fromList([1]),
    );
    await migrated.raw.close();
    final reopened = await AppDatabase.open(databasePath: path);
    try {
      expect(await reopened.cachedNoteImage(account.cacheKey, 'n', current), [
        1,
      ]);
    } finally {
      await reopened.raw.close();
    }
  });
}
