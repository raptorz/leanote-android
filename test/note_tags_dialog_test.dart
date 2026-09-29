import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gemsnote/ui/note_tags_dialog.dart';

void main() {
  testWidgets(
    'pending input is included on save, failure keeps dialog and supports retry',
    (tester) async {
      List<String>? saved;
      var fail = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => NoteTagsDialog(
                    tags: const ['one'],
                    onSave: (tags) async {
                      saved = tags;
                      if (fail) throw StateError('offline');
                    },
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), ' two ');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(saved, ['one', 'two']);
      expect(find.textContaining('保存失败'), findsOneWidget);
      expect(find.byType(NoteTagsDialog), findsOneWidget);
      fail = false;
      await tester.enterText(find.byType(TextField), 'two');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(saved, ['one', 'two']);
      expect(find.byType(NoteTagsDialog), findsNothing);
    },
  );
}
