import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gemsnote/domain/models/account.dart';
import 'package:gemsnote/domain/models/note_file.dart';
import 'package:gemsnote/repositories/auth_repository.dart';
import 'package:gemsnote/ui/note_files_page.dart';

class FilesRepository implements AuthRepository {
  bool deny = false;
  bool badImage = false;
  int downloads = 0;
  final listModes = <bool>[];
  final imageModes = <bool>[];
  @override
  Future<List<NoteFile>> noteFiles(
    StoredSession session,
    String noteId, {
    bool cachedOnly = false,
  }) async {
    listModes.add(cachedOnly);
    expect(noteId, 'note');
    if (deny) throw StateError('noPermission');
    return const [
      NoteFile(id: 'image', title: 'Photo', type: 'png', isAttachment: false),
      NoteFile(
        id: 'attach',
        title: 'Document',
        type: 'pdf',
        isAttachment: true,
      ),
    ];
  }

  @override
  Future<Uint8List> noteImage(
    StoredSession session,
    String noteId,
    NoteFile file, {
    bool cachedOnly = false,
  }) async {
    imageModes.add(cachedOnly);
    downloads++;
    if (deny) throw StateError('noPermission');
    return badImage
        ? Uint8List.fromList([0])
        : File('assets/images/gemsnote_s.png').readAsBytesSync();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('explicit offline toggle reaches cached list and image methods', (
    tester,
  ) async {
    final repo = FilesRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: NoteFilesPage(
          repository: repo,
          session: StoredSession(
            account: Account(
              userId: 'u',
              server: Uri.parse('https://example.test'),
              username: 'u',
              email: '',
              logo: '',
            ),
            token: 'test',
          ),
          noteId: 'note',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('离线缓存'));
    await tester.pumpAndSettle();
    expect(repo.listModes, [false, true]);
    await tester.tap(find.text('Photo'));
    await tester.pumpAndSettle();
    expect(repo.imageModes, [true]);
  });
  Future<void> mount(WidgetTester tester, FilesRepository repo) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NoteFilesPage(
          repository: repo,
          session: StoredSession(
            account: Account(
              userId: 'user',
              server: Uri.parse('https://example.test'),
              username: 'user',
              email: '',
              logo: '',
            ),
            token: 'test',
          ),
          noteId: 'note',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'lists files without downloading; only image opens zoomable preview',
    (tester) async {
      final repo = FilesRepository();
      await mount(tester, repo);
      expect(repo.downloads, 0);
      final attachment = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Document'),
          matching: find.byType(ListTile),
        ),
      );
      expect(attachment.onTap, isNull);
      await tester.tap(find.text('Photo'));
      await tester.pumpAndSettle();
      expect(repo.downloads, 1);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as ResizeImage).policy, ResizeImagePolicy.fit);
    },
  );
  testWidgets(
    'revocation errors do not open image and failed refresh removes visible stale list',
    (tester) async {
      final repo = FilesRepository();
      await mount(tester, repo);
      repo.deny = true;
      await tester.tap(find.text('Photo'));
      await tester.pumpAndSettle();
      expect(find.textContaining('读取图片失败'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsNothing);
      await tester.tap(find.byTooltip('刷新文件列表'));
      await tester.pumpAndSettle();
      expect(find.text('Photo'), findsNothing);
      expect(find.textContaining('读取文件列表失败'), findsOneWidget);
      repo.deny = false;
      await tester.tap(find.byTooltip('刷新文件列表'));
      await tester.pumpAndSettle();
      expect(find.text('Photo'), findsOneWidget);
    },
  );
  testWidgets('bad image bytes show decode error instead of blank page', (
    tester,
  ) async {
    final repo = FilesRepository()..badImage = true;
    await mount(tester, repo);
    await tester.tap(find.text('Photo'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('无法解码图片，请返回重试'), findsOneWidget);
  });
}
