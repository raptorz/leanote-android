import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gemsnote/core/api/api2_client.dart';
import 'package:gemsnote/data/database/app_database.dart';
import 'package:gemsnote/data/session/session_store.dart';
import 'package:gemsnote/domain/models/account.dart';
import 'package:gemsnote/domain/models/notebook.dart';
import 'package:gemsnote/repositories/auth_repository.dart';
import 'package:gemsnote/services/shared_text_inbox.dart';
import 'package:gemsnote/sync/sync_coordinator.dart';
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const run = String.fromEnvironment('SHARE_IMPORT_RUN');
  testWidgets('native inbox claim, offline import, retry and acknowledge', (
    tester,
  ) async {
    expect(RegExp(r'^[0-9a-f]{22}$').hasMatch(run), isTrue);
    final directory = await (await getTemporaryDirectory()).createTemp(
      'share-import-',
    );
    final path = '${directory.path}/notes.sqlite';
    var db = await AppDatabase.open(databasePath: path);
    final inbox = SharedTextInbox();
    final client = MockClient(
      (_) async => throw StateError('Import must stay offline'),
    );
    final api = Api2Client(httpClient: client);
    final session = StoredSession(
      account: Account(
        userId: 'fixture',
        server: Uri.parse('https://import-test.invalid'),
        username: 'fixture',
        email: '',
        logo: '',
      ),
      token: 'unused-test-token',
    );
    AuthRepository repository() => AuthRepository(
      api,
      db,
      const SecureSessionStore(),
      SyncCoordinator(api, db),
    );
    var repo = repository();
    final ids = [for (var i = 0; i < 3; i++) '${run}0$i'];
    try {
      await db.replaceSnapshot(
        account: session.account,
        notebooks: [
          Notebook.fromJson({'NotebookId': 'book', 'Title': 'Test notebook'}),
        ],
        notes: [],
        tags: [],
        lastSyncUsn: 2,
      );
      await inbox.start();
      for (final id in ids) {
        expect(inbox.error, isNull);
        final source = inbox.pending!;
        // Never claim or delete another share, even on an incorrectly prepared simulator.
        expect(source.id, id);
        expect(source.accountKey, isEmpty);
        if (source.hasResource) {
          await expectLater(
            inbox.readResource(source, session.account.cacheKey),
            throwsA(isA<PlatformException>()),
          );
        }
        await inbox.claim(source, session.account.cacheKey);
        await inbox.refresh();
        final claimed = inbox.pending!;
        expect(claimed.accountKey, session.account.cacheKey);
        await expectLater(
          inbox.claim(claimed, 'another-account'),
          throwsA(isA<PlatformException>()),
        );
        Uint8List? bytes;
        if (source.hasResource) {
          await expectLater(
            inbox.readResource(claimed, 'another-account'),
            throwsA(isA<PlatformException>()),
          );
          bytes = await inbox.readResource(claimed, session.account.cacheKey);
          expect(bytes.length, source.resourceSize);
        }
        final note = await repo.importSharedText(
          session,
          claimed,
          'book',
          resourceBytes: bytes,
        );
        expect(note.noteId, id);
        expect(note.content, source.text);
        expect(await db.pendingNoteIds(session.account.cacheKey), contains(id));
        // Native acknowledgment has not happened. Reopen the real SQLite file
        // and retry after an edit to model a process death at this boundary.
        await db.saveEditedText(
          session.account.cacheKey,
          id,
          'Edited',
          'Preserved $id',
        );
        await db.raw.close();
        db = await AppDatabase.open(databasePath: path);
        repo = repository();
        final retry = await repo.importSharedText(
          session,
          claimed,
          'book',
          resourceBytes: bytes,
        );
        expect(retry.title, 'Edited');
        expect(retry.content, 'Preserved $id');
        if (source.hasResource) {
          final task = (await repo.pendingAttachments(session))
              .where((item) => item.noteId == id)
              .single;
          expect(task.isImage, source.resourceKind == 'image');
          expect(task.state, 'pending');
          final staged = await repo.stagedAttachment(session, task.id);
          if (!task.isImage) expect(staged.bytes, [0, 1, 2, 127, 128, 255]);
          expect(staged.bytes, isNotEmpty);
        }
        await inbox.acknowledge(claimed);
        expect(inbox.pending?.id, isNot(id));
        if (source.hasResource) {
          await expectLater(
            inbox.readResource(claimed, session.account.cacheKey),
            throwsA(isA<PlatformException>()),
          );
        }
      }
      expect((await db.notes(session.account.cacheKey)).length, 3);
      expect((await repo.pendingAttachments(session)).length, 2);
      expect(await db.lastSyncUsn(session.account.cacheKey), 2);
      expect(inbox.pending, isNull);
    } finally {
      inbox.dispose();
      client.close();
      if (db.raw.isOpen) await db.raw.close();
      await directory.delete(recursive: true);
    }
  }, skip: !Platform.isIOS || run.isEmpty);
}
