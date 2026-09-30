import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gemsnote/domain/models/account.dart';
import 'package:gemsnote/domain/models/note.dart';
import 'package:gemsnote/domain/models/shared_note.dart';
import 'package:gemsnote/repositories/auth_repository.dart';
import 'package:gemsnote/ui/note_reader_page.dart';
import 'package:gemsnote/ui/shared_notes_page.dart';
import 'package:webview_flutter/webview_flutter.dart';

class SharedRepository implements AuthRepository {
  SharedRepository(this.shared);
  final SharedNote shared;
  bool deny = false;
  bool failList = false;
  @override
  Future<List<SharedNote>> sharedNotes(StoredSession session) async {
    if (failList) throw StateError('snapshotExpired');
    return [shared];
  }

  @override
  Future<Note> sharedContent(StoredSession session, SharedNote note) async {
    if (deny) throw StateError('noPermission');
    return note.note;
  }

  // No database writes, personal-note reads or upload calls are allowed.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final session = StoredSession(
    account: Account(
      userId: 'u',
      server: Uri.parse('https://example.test/'),
      username: 'u',
      email: '',
      logo: '',
    ),
    token: 'test',
  );
  SharedNote note(bool markdown) => SharedNote(
    version: 'version',
    note: Note.fromJson({
      'NoteId': 'note',
      'UserId': 'owner',
      'Title': 'Shared title',
      'Content': markdown
          ? '# Shared body'
          : '<p>Shared body</p><img src="https://other.test/tracker">',
      'IsMarkdown': markdown,
    }),
  );

  for (final markdown in [true, false]) {
    testWidgets(
      'shared preview is read-only with no WebView: markdown=$markdown',
      (tester) async {
        final repo = SharedRepository(note(markdown));
        await tester.pumpWidget(
          MaterialApp(
            home: SharedNotesPage(repository: repo, session: session),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Shared title'));
        await tester.pumpAndSettle();
        expect(find.byType(NoteReaderPage), findsOneWidget);
        expect(find.byTooltip('编辑'), findsNothing);
        expect(find.byType(PopupMenuButton<String>), findsNothing);
        expect(find.byType(WebViewWidget), findsNothing);
        if (!markdown) {
          expect(find.text(repo.shared.note.content), findsOneWidget);
        }
      },
    );
  }

  testWidgets(
    'denied body remains closed and failed refresh removes stale list',
    (tester) async {
      final repo = SharedRepository(note(true))..deny = true;
      await tester.pumpWidget(
        MaterialApp(
          home: SharedNotesPage(repository: repo, session: session),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shared title'));
      await tester.pumpAndSettle();
      expect(find.byType(NoteReaderPage), findsNothing);
      expect(find.textContaining('noPermission'), findsOneWidget);
      repo.failList = true;
      await tester.tap(find.byTooltip('刷新共享列表'));
      await tester.pumpAndSettle();
      expect(find.text('Shared title'), findsNothing);
      expect(find.textContaining('snapshotExpired'), findsOneWidget);
      repo.failList = false;
      await tester.tap(find.byTooltip('刷新共享列表'));
      await tester.pumpAndSettle();
      expect(find.text('Shared title'), findsOneWidget);
    },
  );
}
