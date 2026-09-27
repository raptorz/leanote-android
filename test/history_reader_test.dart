import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gemsnote/domain/models/note.dart';
import 'package:gemsnote/ui/note_reader_page.dart';

void main() {
  testWidgets('history preview has no editing or mutation actions', (
    tester,
  ) async {
    final note = Note.fromJson({
      'NoteId': 'n',
      'Title': 'History',
      'Content': 'Historical body',
      'IsMarkdown': true,
    });
    await tester.pumpWidget(
      MaterialApp(home: NoteReaderPage(note: note, readOnly: true)),
    );
    expect(find.text('Historical body'), findsOneWidget);
    expect(find.byTooltip('编辑'), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
  });
}
