import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gemsnote/domain/models/attachment_upload.dart';
import 'package:gemsnote/ui/attachment_upload_dialog.dart';

void main() {
  testWidgets('upload failure clears password and blocks repeated mutation', (
    tester,
  ) async {
    var calls = 0;
    final pending = Completer<bool>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttachmentUploadDialog(
            identity: 'u',
            file: AttachmentUpload(name: 'a.txt', bytes: Uint8List(1)),
            upload: (_, password) {
              expect(password, 'p');
              calls++;
              return pending.future;
            },
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).last, 'p');
    await tester.tap(find.text('上传'));
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '取消'))
          .onPressed,
      isNull,
    );
    pending.completeError(StateError('network'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      '',
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(find.textContaining('不要重复上传'), findsOneWidget);
    expect(calls, 1);
  });
}
