import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gemsnote/domain/models/account.dart';
import 'package:gemsnote/domain/models/note.dart';
import 'package:gemsnote/domain/models/file_cache_usage.dart';
import 'package:gemsnote/domain/models/note_file.dart';
import 'package:gemsnote/repositories/auth_repository.dart';
import 'package:gemsnote/ui/workspace_page.dart';

import 'foreground_sync_test.dart' show ForegroundRepository;

class CacheRepository extends ForegroundRepository {
  int fileLists = 0;
  final gate = Completer<List<NoteFile>>();
  @override
  Future<List<Note>> notes(
    String accountId, {
    String? notebookId,
    bool starredOnly = false,
    bool trashOnly = false,
  }) async => [
    Note.fromJson({'NoteId': 'n', 'Usn': 1}),
    Note.fromJson({'NoteId': 'new', 'Usn': 0}),
  ];
  @override
  Future<List<NoteFile>> noteFiles(
    StoredSession session,
    String id, {
    bool cachedOnly = false,
  }) {
    expect(id, 'n');
    fileLists++;
    return gate.future;
  }
}

void main() {
  testWidgets(
    'cache management waits for running queue before measuring and clearing',
    (tester) async {
      final repo = ManagedCacheRepository();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        MaterialApp(
          home: WorkspacePage(
            repository: repo,
            session: StoredSession(
              account: Account(
                userId: 'u',
                server: Uri.parse('https://notes.test'),
                username: 'u',
                email: '',
                logo: '',
              ),
              token: 't',
            ),
            onSignedOut: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> choose(String value) async {
        await tester.tap(find.byTooltip('账号菜单'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byWidgetPredicate(
            (w) => w is PopupMenuItem<String> && w.value == value,
          ),
        );
        await tester.pump();
      }

      await tester.tap(find.byTooltip('账号菜单'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is CheckedPopupMenuItem<String> && w.value == 'autoCache',
        ),
      );
      await tester.pumpAndSettle();
      await choose('cacheFiles');
      await tester.pumpAndSettle();
      expect(repo.fileLists, 1);
      await choose('manageCache');
      await tester.pump(const Duration(milliseconds: 400));
      expect(repo.measures, 0);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      repo.gate.complete([]);
      await tester.pumpAndSettle();
      expect(repo.measures, 1);
      expect(repo.clears, 0);
      await tester.tap(find.text('清理缓存'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认清理'));
      await tester.pumpAndSettle();
      expect(repo.clears, 1);
      expect(find.text('离线资源缓存已清理'), findsOneWidget);
    },
  );

  testWidgets(
    'opt-in caching starts after sync closes; failure is separate from dirty status',
    (tester) async {
      final repo = CacheRepository();
      final session = StoredSession(
        account: Account(
          userId: 'u',
          server: Uri.parse('https://notes.test'),
          username: 'u',
          email: '',
          logo: '',
        ),
        token: 'test',
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        MaterialApp(
          home: WorkspacePage(
            repository: repo,
            session: session,
            onSignedOut: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.fileLists, 0);
      await tester.tap(find.byTooltip('账号菜单'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is CheckedPopupMenuItem<String> && w.value == 'autoCache',
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.fileLists, 0);
      await tester.tap(find.byTooltip('账号菜单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('立即同步').first);
      await tester.pumpAndSettle();
      expect(repo.calls, 1);
      expect(repo.fileLists, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(repo.dirty, false);
      expect(find.textContaining('正在准备离线资源缓存'), findsOneWidget);
      repo.gate.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.textContaining('失败 1 项'), findsOneWidget);
      expect(repo.dirty, false);
      expect(find.textContaining('同步失败'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class ManagedCacheRepository extends CacheRepository {
  int measures = 0;
  int clears = 0;
  @override
  Future<FileCacheUsage> fileCacheUsage(StoredSession session) async {
    measures++;
    return const FileCacheUsage(files: 1, bytes: 3);
  }

  @override
  Future<void> clearFileCache(StoredSession session) async {
    clears++;
  }
}
