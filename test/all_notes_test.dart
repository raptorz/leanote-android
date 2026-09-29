import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gemsnote/core/api/api2_client.dart';
import 'package:gemsnote/data/database/app_database.dart';
import 'package:gemsnote/domain/models/account.dart';
import 'package:gemsnote/domain/models/note.dart';
import 'package:gemsnote/repositories/auth_repository.dart';
import 'package:gemsnote/sync/sync_coordinator.dart';
import 'package:gemsnote/ui/workspace_page.dart';
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'data/cached_login_test.dart' show MemorySessions;

void main() {
  testWidgets(
    'all notes includes orphan notes without notebooks and preserves sort on reopen',
    (tester) async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      late AppDatabase db;
      final account = Account(
        userId: 'u',
        server: Uri.parse('https://example.test/'),
        username: 'u',
        email: '',
        logo: '',
      );
      await tester.runAsync(() async {
        db = await AppDatabase.open(databasePath: inMemoryDatabasePath);
        await db.replaceSnapshot(
          account: account,
          notebooks: [],
          tags: [],
          lastSyncUsn: 3,
          notes: [
            Note.fromJson({
              'NoteId': 'a',
              'NotebookId': 'missing',
              'Title': 'Alpha',
              'UpdatedTime': '2026-01-01',
            }),
            Note.fromJson({
              'NoteId': 'b',
              'NotebookId': '',
              'Title': 'Beta',
              'UpdatedTime': '2026-02-01',
            }),
            Note.fromJson({'NoteId': 'c', 'Title': 'Trash', 'IsTrash': true}),
          ],
        );
      });
      addTearDown(db.raw.close);
      final api = Api2Client(
        httpClient: MockClient(
          (_) async => throw StateError('must stay offline'),
        ),
      );
      final repo = AuthRepository(
        api,
        db,
        MemorySessions(),
        SyncCoordinator(api, db),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: WorkspacePage(
            repository: repo,
            session: StoredSession(account: account, token: 'test-token'),
            onSignedOut: () {},
          ),
        ),
      );
      Future<void> settleDatabase() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
      }

      await settleDatabase();
      await tester.tap(find.text('所有笔记'));
      await settleDatabase();
      expect(find.text('Trash'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Beta')).dy,
        lessThan(tester.getTopLeft(find.text('Alpha')).dy),
      );
      await tester.tap(find.byTooltip('笔记排序'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('标题：升序'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Alpha')).dy,
        lessThan(tester.getTopLeft(find.text('Beta')).dy),
      );
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await tester.tap(find.text('所有笔记'));
      await settleDatabase();
      expect(
        tester.getTopLeft(find.text('Alpha')).dy,
        lessThan(tester.getTopLeft(find.text('Beta')).dy),
      );
    },
  );
}
