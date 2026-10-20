import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gemsnote/core/api/api2_client.dart';
import 'package:gemsnote/core/api/api_exception.dart';
import 'package:gemsnote/data/database/app_database.dart';
import 'package:gemsnote/domain/models/attachment_upload.dart';
import 'package:gemsnote/sync/sync_coordinator.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opt-in destructive test: use only a disposable, loopback server/database.
/// No credentials or response bodies are written to test output.
class _Api2OnlyClient extends http.BaseClient {
  final _inner = http.Client();
  final paths = <String>[];
  bool loseNextCreateResponse = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.host != '127.0.0.1' ||
        request.url.port != 19090 ||
        !request.url.path.startsWith('/api2/')) {
      throw StateError('Test attempted a request outside its API2 server');
    }
    paths.add(request.url.path);
    final response = await _inner.send(request);
    if (loseNextCreateResponse && request.url.path == '/api2/client/note/add') {
      loseNextCreateResponse = false;
      // The real server committed the request. Lose only its response, so the
      // next sync must reconcile the stable client ID without another note.
      await response.stream.drain<void>();
      throw const SocketException('Injected lost create response');
    }
    return response;
  }

  @override
  void close() => _inner.close();
}

void main() {
  final enabled = Platform.environment['GEMSNOTE_DISPOSABLE_API2'] == '1';
  setUpAll(() {
    if (!enabled) return;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  test(
    'real API2 notebook and tag deletion converge through incremental sync',
    () async {
      final client = _Api2OnlyClient();
      addTearDown(client.close);
      final api = Api2Client(httpClient: client);
      final server = Uri.parse('http://127.0.0.1:19090/');
      final login = await api.login(
        server: server,
        identity: 'admin',
        password: 'gemsnote',
      );
      final account = login.account;
      final token = login.token;
      final db = await AppDatabase.open(databasePath: inMemoryDatabasePath);
      addTearDown(db.raw.close);
      await db.replaceSnapshot(
        account: account,
        notebooks: [],
        notes: [],
        tags: [],
        lastSyncUsn: 0,
      );
      final sync = SyncCoordinator(api, db);
      final run = DateTime.now().microsecondsSinceEpoch;
      final parent = await api.saveNotebook(
        server: server,
        token: token,
        title: 'Parent $run',
      );
      final child = await api.saveNotebook(
        server: server,
        token: token,
        title: 'Child $run',
        parentNotebookId: parent.notebookId,
      );
      final renamed = await api.saveNotebook(
        server: server,
        token: token,
        title: '重命名 $run',
        existing: child,
      );
      expect(renamed.parentNotebookId, parent.notebookId);
      await sync.synchronize(account: account, token: token);
      expect(
        (await db.notebooks(account.cacheKey))
            .singleWhere((book) => book.notebookId == child.notebookId)
            .title,
        renamed.title,
      );
      await expectLater(
        api.deleteNotebook(server: server, token: token, notebook: parent),
        throwsA(
          isA<ApiException>().having(
            (error) => error.code,
            'reason',
            '笔记本下有子笔记本',
          ),
        ),
      );
      await expectLater(
        api.deleteNotebook(server: server, token: token, notebook: child),
        throwsA(
          isA<ApiException>().having(
            (error) => error.code,
            'reason',
            'conflict',
          ),
        ),
      );
      await api.deleteNotebook(server: server, token: token, notebook: renamed);
      await sync.synchronize(account: account, token: token);
      expect(
        (await db.notebooks(account.cacheKey)).map((book) => book.notebookId),
        isNot(contains(child.notebookId)),
      );
      final currentParent = (await db.notebooks(account.cacheKey))
          .singleWhere((book) => book.notebookId == parent.notebookId);
      await api.deleteNotebook(
        server: server,
        token: token,
        notebook: currentParent,
      );
      await sync.synchronize(account: account, token: token);
      expect(
        (await db.notebooks(account.cacheKey)).map((book) => book.notebookId),
        isNot(contains(parent.notebookId)),
      );

      final tag = '临时标签 $run';
      final createdUsn = await api.createTag(
        server: server,
        token: token,
        userId: account.userId,
        name: tag,
      );
      final taggedBook = await api.saveNotebook(
        server: server,
        token: token,
        title: 'Tag references $run',
      );
      await sync.synchronize(account: account, token: token);
      final taggedIds = <bool, String>{};
      for (final trash in [false, true]) {
        final note = await db.createLocalNote(
          account: account,
          notebookId: taggedBook.notebookId,
          isMarkdown: true,
          title: 'Tagged $trash $run',
          content: 'Keep body $trash',
        );
        taggedIds[trash] = note.noteId;
        await db.saveLocalNote(
          account.cacheKey,
          note.copyWith(tags: [tag], isTrash: trash),
        );
      }
      await sync.synchronize(account: account, token: token);
      for (final trash in [false, true]) {
        final note = (await db.notes(
          account.cacheKey,
          trashOnly: trash,
        )).singleWhere((note) => note.noteId == taggedIds[trash]);
        expect(note.tags, [tag]);
      }
      expect(
        await db.tagCounts(account.cacheKey, includeUnused: true),
        contains(tag),
      );
      final checkpoint = await db.lastSyncUsn(account.cacheKey);
      final deletedUsn = await api.deleteTag(
        server: server,
        token: token,
        name: tag,
        usn: createdUsn,
      );
      expect(deletedUsn, greaterThan(checkpoint));
      final changes = await api.getTags(
        server: server,
        token: token,
        afterUsn: checkpoint,
      );
      expect(
        changes.singleWhere((item) => item['Tag'] == tag)['IsDeleted'],
        isTrue,
      );
      await sync.synchronize(account: account, token: token);
      expect(
        await db.tagCounts(account.cacheKey, includeUnused: true),
        isNot(contains(tag)),
      );
      for (final trash in [false, true]) {
        final note = (await db.notes(
          account.cacheKey,
          trashOnly: trash,
        )).singleWhere((note) => note.noteId == taggedIds[trash]);
        expect(note.tags, isEmpty);
        expect(note.content, 'Keep body $trash');
        expect(note.isTrash, trash);
        expect(note.usn, greaterThan(checkpoint));
      }
      expect(
        await db.lastSyncUsn(account.cacheKey),
        greaterThanOrEqualTo(deletedUsn),
      );
      await api.logout(server: server, token: token);
    },
    skip: enabled
        ? false
        : 'Requires an explicitly disposable local API2 server',
    timeout: const Timeout(Duration(minutes: 2)),
  );
  for (final scenario in ['upload', 'lostResponse', 'history']) {
    final restore = scenario == 'history';
    test(
      restore
          ? 'real API2 subsequent edit and complete history restore'
          : 'real API2 two-client sync and binary upload: $scenario',
      () async {
        final client = _Api2OnlyClient();
        addTearDown(client.close);
        final api = Api2Client(httpClient: client);
        final server = Uri.parse('http://127.0.0.1:19090/');
        final login = await api.login(
          server: server,
          identity: 'admin',
          password: 'gemsnote',
        );
        final account = login.account;
        final token = login.token;
        final db = await AppDatabase.open(databasePath: inMemoryDatabasePath);
        addTearDown(db.raw.close);
        final secondDb = await AppDatabase.open(
          databasePath: inMemoryDatabasePath,
        );
        addTearDown(secondDb.raw.close);
        for (final local in [db, secondDb]) {
          await local.replaceSnapshot(
            account: account,
            notebooks: [],
            notes: [],
            tags: [],
            lastSyncUsn: 0,
          );
        }
        final sync = SyncCoordinator(api, db);
        final secondSync = SyncCoordinator(api, secondDb);
        final run = DateTime.now().microsecondsSinceEpoch;
        final notebook = await api.saveNotebook(
          server: server,
          token: token,
          title: 'Mobile live test $run',
        );
        await sync.synchronize(account: account, token: token);
        expect(
          (await db.notebooks(account.cacheKey)).map((n) => n.notebookId),
          contains(notebook.notebookId),
        );
        final draft = await db.createLocalNote(
          account: account,
          notebookId: notebook.notebookId,
          isMarkdown: true,
          title: '离线笔记 $run',
          content: '# 第一版\n中文与 emoji 📝\n',
        );
        expect(
          await db.pendingNoteIds(account.cacheKey),
          contains(draft.noteId),
        );
        if (scenario == 'lostResponse') {
          client.loseNextCreateResponse = true;
          await expectLater(
            sync.synchronize(account: account, token: token),
            throwsA(isA<ApiException>()),
          );
          expect(client.loseNextCreateResponse, isFalse);
          expect(
            await db.pendingNoteIds(account.cacheKey),
            contains(draft.noteId),
          );
        }
        await sync.synchronize(account: account, token: token);
        expect(await db.pendingNoteIds(account.cacheKey), isEmpty);
        await secondSync.synchronize(account: account, token: token);
        final first = (await secondDb.searchableNote(
          account.cacheKey,
          draft.noteId,
        ))!;
        expect(first.content, draft.content);
        expect(first.isMarkdown, isTrue);
        expect(
          (await secondDb.notes(account.cacheKey))
              .where((note) => note.title == draft.title),
          hasLength(1),
        );

        final bytes = Uint8List.fromList([0, 1, 2, 127, 128, 255]);
        final attachmentId = await api.uploadAttachment(
          server: server,
          token: token,
          userId: account.userId,
          identity: 'admin',
          password: 'gemsnote',
          noteId: draft.noteId,
          file: AttachmentUpload(name: '原件.bin', bytes: bytes),
        );
        final files = await api.noteFiles(
          server: server,
          token: token,
          userId: account.userId,
          noteId: draft.noteId,
        );
        final file = files.singleWhere((file) => file.id == attachmentId);
        expect(
          await api.noteAttachment(
            server: server,
            token: token,
            noteId: draft.noteId,
            userId: account.userId,
            file: file,
          ),
          bytes,
        );
        if (!restore) {
          await secondSync.synchronize(account: account, token: token);
          expect(
            (await secondDb.searchableNote(
              account.cacheKey,
              draft.noteId,
            ))!.content,
            draft.content,
          );
          await api.logout(server: server, token: token);
          return;
        }
        await sync.synchronize(account: account, token: token);
        await db.saveEditedText(
          account.cacheKey,
          draft.noteId,
          '第二版 $run',
          '第二版正文',
        );
        await sync.synchronize(account: account, token: token);
        await expectLater(
          api.updateNote(
            server: server,
            token: token,
            note: first.copyWith(content: 'stale writer'),
          ),
          throwsA(isA<ApiException>()),
        );
        final histories = await api.getHistories(
          server: server,
          token: token,
          noteId: draft.noteId,
        );
        final matching = <String>[];
        for (final history in histories.where((h) => h.filesComplete)) {
          final content = await api.getHistoryContent(
            server: server,
            token: token,
            noteId: draft.noteId,
            historyId: history.id,
          );
          if (content == draft.content) matching.add(history.id);
        }
        expect(matching, isNotEmpty);
        final current = (await db.searchableNote(
          account.cacheKey,
          draft.noteId,
        ))!;
        await api.restoreHistorySnapshot(
          server: server,
          token: token,
          noteId: draft.noteId,
          historyId: matching.first,
          usn: current.usn,
        );
        await secondSync.synchronize(account: account, token: token);
        expect(
          (await secondDb.searchableNote(
            account.cacheKey,
            draft.noteId,
          ))!.content,
          draft.content,
        );
        final restoredFiles = await api.noteFiles(
          server: server,
          token: token,
          noteId: draft.noteId,
          userId: account.userId,
        );
        expect(restoredFiles.map((file) => file.id), contains(attachmentId));
        expect(
          await api.noteAttachment(
            server: server,
            token: token,
            noteId: draft.noteId,
            userId: account.userId,
            file: restoredFiles.singleWhere((file) => file.id == attachmentId),
          ),
          bytes,
        );
        expect(client.paths, contains('/api2/note/restoreHistory'));
        await api.logout(server: server, token: token);
      },
      skip: enabled
          ? false
          : 'Requires an explicitly disposable local API2 server',
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
