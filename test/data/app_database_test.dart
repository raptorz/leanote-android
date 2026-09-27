import 'package:flutter_test/flutter_test.dart';
import 'package:gemsnote/data/database/app_database.dart';
import 'package:gemsnote/domain/models/account.dart';
import 'package:gemsnote/domain/models/note.dart';
import 'package:gemsnote/domain/models/notebook.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('fresh snapshot is committed as one offline account cache', () async {
    final database = await AppDatabase.open(databasePath: inMemoryDatabasePath);
    const userId = '507f1f77bcf86cd799439011';
    final account = Account(
      userId: userId,
      server: Uri.parse('https://notes.example.test/'),
      username: 'admin',
      email: 'admin@example.test',
      logo: '',
    );
    const notebook = Notebook(
      notebookId: '507f1f77bcf86cd799439012',
      parentNotebookId: '',
      title: 'Life',
      sequence: 1,
      usn: 2,
      numberNotes: 1,
      isDeleted: false,
    );
    const note = Note(
      noteId: '507f1f77bcf86cd799439013',
      notebookId: '507f1f77bcf86cd799439012',
      userId: userId,
      title: '珠玑笔记',
      content: '日积字句，终得珠玑。',
      tags: ['Gemsnote'],
      usn: 3,
      isMarkdown: true,
      isStarred: true,
      isTrash: false,
      isDeleted: false,
      createdTime: '2026-01-01T00:00:00Z',
      updatedTime: '2026-01-02T00:00:00Z',
    );

    await database.replaceSnapshot(
      account: account,
      notebooks: const [notebook],
      notes: const [note],
      tags: const [
        {'Tag': 'Gemsnote', 'Usn': 3},
      ],
      lastSyncUsn: 3,
    );

    expect((await database.activeAccount())?.userId, userId);
    expect((await database.notebooks(account.cacheKey)).single.title, 'Life');
    final cached = (await database.notes(account.cacheKey)).single;
    expect(cached.content, '日积字句，终得珠玑。');
    expect(cached.isStarred, isTrue);

    final draft = await database.createLocalNote(
      account: account,
      notebookId: notebook.notebookId,
      isMarkdown: true,
    );
    await database.saveLocalNote(
      account.cacheKey,
      draft.copyWith(title: '离线草稿', content: '# 草稿'),
    );
    final dirty = await database.dirtyNotes(account.cacheKey);
    expect(dirty, hasLength(1));
    expect(dirty.single.noteId, hasLength(24));
    expect(dirty.single.title, '离线草稿');

    await database.saveLocalNote(
      account.cacheKey,
      note.copyWith(isStarred: true, notebookId: notebook.notebookId),
    );
    final starred = await database.notes(account.cacheKey, starredOnly: true);
    expect(starred.single.noteId, note.noteId);
    expect(await database.dirtyNotes(account.cacheKey), hasLength(2));
    expect(
      (await database.searchNotes(account.cacheKey, '珠玑')).single.noteId,
      note.noteId,
    );
    await database.saveLocalNote(
      account.cacheKey,
      draft.copyWith(title: '回收站草稿', isTrash: true),
    );
    final trash = await database.notes(account.cacheKey, trashOnly: true);
    expect(trash.single.noteId, draft.noteId);

    await database.mergeChanges(
      account: account,
      notebooks: const [],
      notes: [
        note.copyWith(title: '服务端标题', usn: 8),
        draft.copyWith(isDeleted: true, usn: 9),
      ],
      tags: const [],
      lastSyncUsn: 9,
    );
    final merged = await database.notes(account.cacheKey);
    expect(merged, hasLength(1));
    expect(merged.single.title, '服务端标题');
    expect(await database.lastSyncUsn(account.cacheKey), 9);
    await database.raw.close();
  });
}
