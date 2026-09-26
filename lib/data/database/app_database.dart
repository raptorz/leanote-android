import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/models/account.dart';
import '../../domain/models/note.dart';
import '../../domain/models/notebook.dart';

class AppDatabase {
  AppDatabase._(this.raw);

  static const schemaVersion = 1;
  final Database raw;

  static Future<AppDatabase> open({String? databasePath}) async {
    final filePath =
        databasePath ??
        path.join(
          (await getApplicationSupportDirectory()).path,
          'gemsnote.sqlite',
        );
    final database = await openDatabase(
      filePath,
      version: schemaVersion,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) async {
        for (final statement in _schema) {
          await db.execute(statement);
        }
      },
    );
    return AppDatabase._(database);
  }

  Future<Account?> activeAccount() async {
    final rows = await raw.query('accounts', where: 'is_active = 1', limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.single;
    return Account(
      userId: row['user_id']! as String,
      server: Uri.parse(row['server']! as String),
      username: row['username']! as String,
      email: row['email']! as String,
      logo: row['logo']! as String,
    );
  }

  Future<void> replaceSnapshot({
    required Account account,
    required List<Notebook> notebooks,
    required List<Note> notes,
    required List<Map<String, Object?>> tags,
    required int lastSyncUsn,
  }) async {
    await raw.transaction((txn) async {
      final batch = txn.batch();
      batch.update('accounts', {'is_active': 0});
      batch.insert('accounts', {
        'account_id': account.cacheKey,
        'user_id': account.userId,
        'server': account.server.toString(),
        'username': account.username,
        'email': account.email,
        'logo': account.logo,
        'last_sync_usn': lastSyncUsn,
        'is_active': 1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      for (final table in ['notebooks', 'notes', 'tags']) {
        batch.delete(
          table,
          where: 'account_id = ?',
          whereArgs: [account.cacheKey],
        );
      }
      for (final notebook in notebooks.where((item) => !item.isDeleted)) {
        batch.insert('notebooks', {
          'account_id': account.cacheKey,
          'server_id': notebook.notebookId,
          'parent_server_id': notebook.parentNotebookId,
          'title': notebook.title,
          'sequence': notebook.sequence,
          'usn': notebook.usn,
          'number_notes': notebook.numberNotes,
        });
      }
      for (final note in notes.where((item) => !item.isDeleted)) {
        batch.insert('notes', {
          'account_id': account.cacheKey,
          'server_id': note.noteId,
          'notebook_server_id': note.notebookId,
          'owner_server_id': note.userId,
          'title': note.title,
          'content': note.content,
          'tags_json': jsonEncode(note.tags),
          'usn': note.usn,
          'is_markdown': note.isMarkdown ? 1 : 0,
          'is_starred': note.isStarred ? 1 : 0,
          'is_trash': note.isTrash ? 1 : 0,
          'created_time': note.createdTime,
          'updated_time': note.updatedTime,
          'is_dirty': 0,
          'local_is_new': 0,
          'local_is_deleted': 0,
        });
      }
      for (final tag in tags.where((item) => item['IsDeleted'] != true)) {
        final name = tag['Tag']?.toString() ?? tag['Title']?.toString() ?? '';
        if (name.isEmpty) continue;
        batch.insert('tags', {
          'account_id': account.cacheKey,
          'name': name,
          'usn': _integer(tag['Usn']),
        });
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Notebook>> notebooks(String accountId) async {
    final rows = await raw.query(
      'notebooks',
      where: 'account_id = ?',
      whereArgs: [accountId],
      orderBy: 'title COLLATE NOCASE, server_id',
    );
    return rows
        .map(
          (row) => Notebook(
            notebookId: row['server_id']! as String,
            parentNotebookId: row['parent_server_id']! as String,
            title: row['title']! as String,
            sequence: row['sequence']! as int,
            usn: row['usn']! as int,
            numberNotes: row['number_notes']! as int,
            isDeleted: false,
          ),
        )
        .toList(growable: false);
  }

  Future<List<Note>> notes(String accountId, {String? notebookId}) async {
    final clauses = <String>['account_id = ?', 'is_trash = 0'];
    final arguments = <Object?>[accountId];
    if (notebookId != null) {
      clauses.add('notebook_server_id = ?');
      arguments.add(notebookId);
    }
    final rows = await raw.query(
      'notes',
      where: clauses.join(' AND '),
      whereArgs: arguments,
      orderBy: 'updated_time DESC, server_id',
    );
    return rows.map(_noteFromRow).toList(growable: false);
  }

  Future<void> deactivate(String accountId) async {
    await raw.update(
      'accounts',
      {'is_active': 0},
      where: 'account_id = ?',
      whereArgs: [accountId],
    );
  }

  static Note _noteFromRow(Map<String, Object?> row) => Note(
    noteId: row['server_id']! as String,
    notebookId: row['notebook_server_id']! as String,
    userId: row['owner_server_id']! as String,
    title: row['title']! as String,
    content: row['content']! as String,
    tags: (jsonDecode(row['tags_json']! as String) as List)
        .map((item) => item.toString())
        .toList(growable: false),
    usn: row['usn']! as int,
    isMarkdown: row['is_markdown'] == 1,
    isStarred: row['is_starred'] == 1,
    isTrash: row['is_trash'] == 1,
    isDeleted: false,
    createdTime: row['created_time']! as String,
    updatedTime: row['updated_time']! as String,
  );

  static int _integer(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  static const _schema = <String>[
    '''CREATE TABLE accounts (
      account_id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      server TEXT NOT NULL,
      username TEXT NOT NULL,
      email TEXT NOT NULL,
      logo TEXT NOT NULL DEFAULT '',
      last_sync_usn INTEGER NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL DEFAULT 0
    )''',
    '''CREATE TABLE notebooks (
      account_id TEXT NOT NULL,
      server_id TEXT NOT NULL,
      parent_server_id TEXT NOT NULL DEFAULT '',
      title TEXT NOT NULL,
      sequence INTEGER NOT NULL DEFAULT 0,
      usn INTEGER NOT NULL DEFAULT 0,
      number_notes INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (account_id, server_id),
      FOREIGN KEY (account_id) REFERENCES accounts(account_id) ON DELETE CASCADE
    )''',
    '''CREATE TABLE notes (
      account_id TEXT NOT NULL,
      server_id TEXT NOT NULL,
      notebook_server_id TEXT NOT NULL DEFAULT '',
      owner_server_id TEXT NOT NULL,
      title TEXT NOT NULL,
      content TEXT NOT NULL DEFAULT '',
      tags_json TEXT NOT NULL DEFAULT '[]',
      usn INTEGER NOT NULL DEFAULT 0,
      is_markdown INTEGER NOT NULL DEFAULT 0,
      is_starred INTEGER NOT NULL DEFAULT 0,
      is_trash INTEGER NOT NULL DEFAULT 0,
      created_time TEXT NOT NULL DEFAULT '',
      updated_time TEXT NOT NULL DEFAULT '',
      is_dirty INTEGER NOT NULL DEFAULT 0,
      local_is_new INTEGER NOT NULL DEFAULT 0,
      local_is_deleted INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (account_id, server_id),
      FOREIGN KEY (account_id) REFERENCES accounts(account_id) ON DELETE CASCADE
    )''',
    '''CREATE TABLE tags (
      account_id TEXT NOT NULL,
      name TEXT NOT NULL,
      usn INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (account_id, name),
      FOREIGN KEY (account_id) REFERENCES accounts(account_id) ON DELETE CASCADE
    )''',
    'CREATE INDEX notebook_parent_idx ON notebooks(account_id, parent_server_id)',
    'CREATE INDEX note_notebook_idx ON notes(account_id, notebook_server_id)',
    'CREATE INDEX note_dirty_idx ON notes(account_id, is_dirty)',
  ];
}
