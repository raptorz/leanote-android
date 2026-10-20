import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gemsnote/data/database/app_database.dart';
import 'package:gemsnote/data/session/session_store.dart';
import 'package:gemsnote/domain/models/account.dart';
import 'package:gemsnote/domain/models/notebook.dart';
import 'package:gemsnote/ui/visual_html_editor.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native database and secure storage survive reopen', (
    tester,
  ) async {
    final directory = await (await getTemporaryDirectory()).createTemp(
      'gemsnote-device-test-',
    );
    final file = '${directory.path}/notes.sqlite';
    final key = 'device-test-${DateTime.now().microsecondsSinceEpoch}';
    const storage = SecureSessionStore();
    AppDatabase? db;
    try {
      db = await AppDatabase.open(databasePath: file);
      final account = Account(
        userId: '507f1f77bcf86cd799439011',
        server: Uri.parse('https://device-test.invalid'),
        username: 'device-test',
        email: '',
        logo: '',
      );
      const notebookId = '507f1f77bcf86cd799439012';
      await db.replaceSnapshot(
        account: account,
        notebooks: [
          Notebook.fromJson({'NotebookId': notebookId, 'Title': '设备测试'}),
        ],
        notes: [],
        tags: [],
        lastSyncUsn: 1,
      );
      final note = await db.createLocalNote(
        account: account,
        notebookId: notebookId,
        isMarkdown: false,
      );
      const body = '<p>离线正文 <b>保留格式</b></p>';
      await db.saveEditedText(account.cacheKey, note.noteId, '标题', body);
      await storage.write(key, 'device-test-token');
      await db.raw.close();
      db = await AppDatabase.open(databasePath: file);
      final restored = await db.searchableNote(account.cacheKey, note.noteId);
      expect(restored, isNotNull);
      expect(restored!.content, body);
      expect(restored.title, '标题');
      expect(restored.isMarkdown, false);
      expect(await const SecureSessionStore().read(key), 'device-test-token');
    } finally {
      if (db != null && db.raw.isOpen) await db.raw.close();
      await storage.delete(key);
      await directory.delete(recursive: true);
    }
  });

  testWidgets('real WebView edits and undoes rich text without losing source', (
    tester,
  ) async {
    final loaded = Completer<void>();
    final changes = <String>[];
    const original = '<p>设备编辑验证</p>';
    final controller = WebViewController();
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.addJavaScriptChannel(
      'Changes',
      onMessageReceived: (message) => changes.add(message.message),
    );
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) {
          if (!loaded.isCompleted) loaded.complete();
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WebViewWidget(controller: controller)),
      ),
    );
    await controller.loadHtmlString(visualEditorDocument(original));
    await loaded.future.timeout(const Duration(seconds: 90));
    expect(
      await controller.runJavaScriptReturningResult(
        'window.readContent() === "$original"',
      ),
      true,
    );
    await controller.runJavaScript('''
      editor.focus();
      const range = document.createRange();
      range.selectNodeContents(editor.querySelector('p'));
      const selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
      window.format('bold');
    ''');
    expect(
      await controller.runJavaScriptReturningResult(
        "/<(b|strong)>/.test(window.readContent()) && editor.textContent === '设备编辑验证'",
      ),
      true,
    );
    await controller.runJavaScript("window.format('undo')");
    expect(
      await controller.runJavaScriptReturningResult(
        'window.readContent() === "$original"',
      ),
      true,
    );
    await tester.pump();
    expect(changes, isNotEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
