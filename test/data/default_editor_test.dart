import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gemsnote/data/database/app_database.dart';
import 'package:gemsnote/domain/models/account.dart';
import 'package:gemsnote/domain/models/default_editor.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late AppDatabase db;
  late Directory directory;
  late String path;
  Account account(String server, [String user = 'u']) => Account(
    userId: user,
    server: Uri.parse(server),
    username: user,
    email: '',
    logo: '',
  );
  final a = account('https://one.test/');
  final b = account('https://two.test/');
  final c = account('https://one.test/', 'other');
  Future<void> snapshot(Account account) => db.replaceSnapshot(
    account: account,
    notebooks: [],
    notes: [],
    tags: [],
    lastSyncUsn: 3,
  );
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp('gemsnote-editor-');
    path = '${directory.path}/cache.sqlite';
    db = await AppDatabase.open(databasePath: path);
    await snapshot(a);
    await snapshot(b);
    await snapshot(c);
  });
  tearDown(() async {
    await db.raw.close();
    await directory.delete(recursive: true);
  });

  test(
    'preference isolates server and user and survives reopen, logout and reset',
    () async {
      expect(await db.defaultEditor(a.cacheKey), DefaultEditor.html);
      await db.setDefaultEditor(a.cacheKey, DefaultEditor.markdown);
      expect(await db.defaultEditor(b.cacheKey), DefaultEditor.html);
      expect(await db.defaultEditor(c.cacheKey), DefaultEditor.html);
      await db.deactivate(a.cacheKey);
      await db.raw.close();
      db = await AppDatabase.open(databasePath: path);
      expect(await db.defaultEditor(a.cacheKey), DefaultEditor.markdown);
      await snapshot(a);
      expect(await db.defaultEditor(a.cacheKey), DefaultEditor.markdown);
      expect(await db.pendingNoteIds(a.cacheKey), isEmpty);
      expect(await db.lastSyncUsn(a.cacheKey), 3);
    },
  );
  test('v5 migration retains dirty content, cursor and activates default preference', () async {
    final note = await db.createLocalNote(
      account: a,
      notebookId: '',
      isMarkdown: false,
      content: '<p>unsynced</p>',
    );
    await db.raw.execute('DROP TABLE account_preferences');
    await db.raw.setVersion(5);
    await db.raw.close();
    db = await AppDatabase.open(databasePath: path);
    expect(await db.raw.getVersion(), 6);
    expect((await db.dirtyNotes(a.cacheKey)).single.content, '<p>unsynced</p>');
    expect(await db.pendingNoteIds(a.cacheKey), {note.noteId});
    expect(await db.lastSyncUsn(a.cacheKey), 3);
    expect(await db.defaultEditor(a.cacheKey), DefaultEditor.html);
    await db.setDefaultEditor(a.cacheKey, DefaultEditor.markdown);
    expect((await db.dirtyNotes(a.cacheKey)).single.isMarkdown, false);
  });
  test('missing accounts cannot acquire orphan preferences', () async {
    await expectLater(
      db.setDefaultEditor('missing', DefaultEditor.markdown),
      throwsStateError,
    );
    expect(await db.raw.query('account_preferences'), isEmpty);
  });
}
