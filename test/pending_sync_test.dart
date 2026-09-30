import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gemsnote/core/api/api2_client.dart';
import 'package:gemsnote/data/database/app_database.dart';
import 'package:gemsnote/domain/models/account.dart';
import 'package:gemsnote/domain/models/notebook.dart';
import 'package:gemsnote/repositories/auth_repository.dart';
import 'package:gemsnote/sync/sync_coordinator.dart';
import 'package:gemsnote/ui/workspace_page.dart';
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'data/cached_login_test.dart' show MemorySessions;

void main() {
  testWidgets(
    'pending badges survive a failed upload with a persistent error',
    (tester) async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      late AppDatabase db;
      final account = Account(
        userId: '507f1f77bcf86cd799439011',
        server: Uri.parse('https://notes.example.test/'),
        username: 'admin',
        email: '',
        logo: '',
      );
      const notebook = Notebook(
        notebookId: '507f1f77bcf86cd799439012',
        parentNotebookId: '',
        title: 'Life',
        sequence: 0,
        usn: 1,
        numberNotes: 0,
        isDeleted: false,
      );
      await tester.runAsync(() async {
        db = await AppDatabase.open(databasePath: inMemoryDatabasePath);
        await db.replaceSnapshot(
          account: account,
          notebooks: [notebook],
          notes: [],
          tags: [],
          lastSyncUsn: 1,
        );
        final draft = await db.createLocalNote(
          account: account,
          notebookId: notebook.notebookId,
          isMarkdown: true,
        );
        await db.saveLocalNote(
          account.cacheKey,
          draft.copyWith(tags: ['mobile']),
        );
      });
      addTearDown(db.raw.close);
      final api = Api2Client(
        httpClient: MockClient((_) async => throw StateError('offline')),
      );
      final repository = AuthRepository(
        api,
        db,
        MemorySessions(),
        SyncCoordinator(api, db),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: WorkspacePage(
            repository: repository,
            session: StoredSession(account: account, token: 'test-token'),
            onSignedOut: () {},
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.byTooltip('立即同步（1 篇待上传）'), findsOneWidget);
      await tester.tap(find.byTooltip('标签'));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('mobile'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('mobile'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('mobile'), findsOneWidget);
      expect(find.byTooltip('本地修改尚未上传'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Life'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.byTooltip('本地修改尚未上传'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('立即同步'));
        // SQLite FFI runs on real event-loop time. A single 100ms delay can
        // leave it pending when pumpAndSettle switches to virtual time.
        // Wait for the existing failure UI, bounded, without weakening assertions.
        for (var attempt = 0; attempt < 100; attempt++) {
          await tester.pump(const Duration(milliseconds: 50));
          await Future<void>.delayed(const Duration(milliseconds: 50));
          if (find.byTooltip('关闭提示').evaluate().isNotEmpty &&
              find.byType(CircularProgressIndicator).evaluate().isEmpty &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty) {
            break;
          }
        }
      });
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.byTooltip('关闭提示'), findsOneWidget);
      expect(find.byTooltip('本地修改尚未上传'), findsOneWidget);
    },
  );
}
