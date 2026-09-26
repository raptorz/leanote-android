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
    await database.raw.close();
  });
}
