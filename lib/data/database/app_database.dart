import 'dart:convert';
import 'dart:math';

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

  Future<int> lastSyncUsn(String accountId) async {
    final rows = await raw.query(
      'accounts',
      columns: ['last_sync_usn'],
      where: 'account_id = ?',
      whereArgs: [accountId],
      limit: 1,
    );
    return rows.isEmpty ? 0 : rows.single['last_sync_usn']! as int;
  }

  Future<bool> hasAccountCache(String accountId) async => (await raw.query(
    'accounts',
    columns: ['account_id'],
    where: 'account_id = ?',
    whereArgs: [accountId],
    limit: 1,
  )).isNotEmpty;

  Future<Account> cachedProfile(Account fallback) async {
    final rows = await raw.query(
      'accounts',
      where: 'account_id = ?',
      whereArgs: [fallback.cacheKey],
      limit: 1,
    );
    if (rows.isEmpty) return fallback;
    final row = rows.single;
    return Account(
      userId: fallback.userId,
      server: fallback.server,
      username: row['username'] as String,
      email: row['email'] as String,
      logo: row['logo'] as String,
    );
  }

  Future<void> updateProfile(Account account) async {
    await raw.update(
      'accounts',
      {
        'username': account.username,
        'email': account.email,
        'logo': account.logo,
      },
      where: 'account_id = ?',
      whereArgs: [account.cacheKey],
    );
  }

  Future<void> activateCachedAccount(Account account) async {
    await raw.transaction((txn) async {
      await txn.update('accounts', {'is_active': 0});
      final changed = await txn.update(
        'accounts',
        {
          'is_active': 1,
          'username': account.username,
          'email': account.email,
          'logo': account.logo,
        },
        where: 'account_id = ?',
        whereArgs: [account.cacheKey],
      );
      if (changed != 1) throw StateError('accountCacheMissing');
    });
  }

  Future<void> replaceSnapshot({
    required Account account,
    required List<Notebook> notebooks,
    required List<Note> notes,
    required List<Map<String, Object?>> tags,
    required int lastSyncUsn,
  }) async {
    await raw.transaction((txn) async {
      final pending = await txn.query(
        'notes',
        columns: ['server_id'],
        where: 'account_id = ? AND is_dirty = 1',
        whereArgs: [account.cacheKey],
        limit: 1,
      );
      if (pending.isNotEmpty) throw StateError('unsyncedChanges');
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

  Future<void> mergeChanges({
    required Account account,
    required List<Notebook> notebooks,
    required List<Note> notes,
    required List<Map<String, Object?>> tags,
    required int lastSyncUsn,
  }) async {
    await raw.transaction((txn) async {
      // New edits may have been saved while the network requests were running.
      // Keep the cursor unchanged so this remote page is retried next time.
      for (final note in notes) {
        final pending = await txn.query(
          'notes',
          columns: ['server_id'],
          where: 'account_id = ? AND server_id = ? AND is_dirty = 1',
          whereArgs: [account.cacheKey, note.noteId],
          limit: 1,
        );
        if (pending.isNotEmpty) throw StateError('localChangesDuringSync');
      }
      final batch = txn.batch();
      for (final notebook in notebooks) {
        if (notebook.isDeleted) {
          batch.delete(
            'notebooks',
            where: 'account_id = ? AND server_id = ?',
            whereArgs: [account.cacheKey, notebook.notebookId],
          );
        } else {
          batch.insert('notebooks', {
            'account_id': account.cacheKey,
            'server_id': notebook.notebookId,
            'parent_server_id': notebook.parentNotebookId,
            'title': notebook.title,
            'sequence': notebook.sequence,
            'usn': notebook.usn,
            'number_notes': notebook.numberNotes,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      for (final note in notes) {
        if (note.isDeleted) {
          batch.delete(
            'notes',
            where: 'account_id = ? AND server_id = ?',
            whereArgs: [account.cacheKey, note.noteId],
          );
        } else {
          _insertNote(batch, account.cacheKey, note);
        }
      }
      for (final tag in tags) {
        final name = tag['Tag']?.toString() ?? tag['Title']?.toString() ?? '';
        if (name.isEmpty) continue;
        if (tag['IsDeleted'] == true) {
          batch.delete(
            'tags',
            where: 'account_id = ? AND name = ?',
            whereArgs: [account.cacheKey, name],
          );
        } else {
          batch.insert('tags', {
            'account_id': account.cacheKey,
            'name': name,
            'usn': _integer(tag['Usn']),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      batch.update(
        'accounts',
        {'last_sync_usn': lastSyncUsn},
        where: 'account_id = ?',
        whereArgs: [account.cacheKey],
      );
      await batch.commit(noResult: true);
    });
  }

  Future<List<Notebook>> notebooks(String accountId) async {
    final rows = await raw.rawQuery(
      '''SELECT notebooks.*,
        (SELECT COUNT(*) FROM notes
          WHERE notes.account_id = notebooks.account_id
            AND notes.notebook_server_id = notebooks.server_id
            AND notes.is_trash = 0
            AND notes.local_is_deleted = 0) AS actual_number_notes
        FROM notebooks
        WHERE notebooks.account_id = ?
        ORDER BY notebooks.title COLLATE NOCASE, notebooks.server_id''',
      [accountId],
    );
    return rows
        .map(
          (row) => Notebook(
            notebookId: row['server_id']! as String,
            parentNotebookId: row['parent_server_id']! as String,
            title: row['title']! as String,
            sequence: row['sequence']! as int,
            usn: row['usn']! as int,
            numberNotes: row['actual_number_notes']! as int,
            isDeleted: false,
          ),
        )
        .toList(growable: false);
  }

  Future<void> cacheNotebook(String accountId, Notebook notebook) async {
    // Do not advance the global cursor: other remote changes may precede this
    // write and still need to be downloaded by the next sync.
    await raw.insert('notebooks', {
      'account_id': accountId,
      'server_id': notebook.notebookId,
      'parent_server_id': notebook.parentNotebookId,
      'title': notebook.title,
      'sequence': notebook.sequence,
      'usn': notebook.usn,
      'number_notes': notebook.numberNotes,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Note>> notes(
    String accountId, {
    String? notebookId,
    bool starredOnly = false,
    bool trashOnly = false,
  }) async {
    final clauses = <String>[
      'account_id = ?',
      trashOnly ? 'is_trash = 1' : 'is_trash = 0',
    ];
    final arguments = <Object?>[accountId];
    if (notebookId != null) {
      clauses.add('notebook_server_id = ?');
      arguments.add(notebookId);
    }
    if (starredOnly) clauses.add('is_starred = 1');
    final rows = await raw.query(
      'notes',
      where: clauses.join(' AND '),
      whereArgs: arguments,
      orderBy: 'updated_time DESC, server_id',
    );
    return rows.map(_noteFromRow).toList(growable: false);
  }

  Future<List<Note>> searchNotes(String accountId, String query) async {
    final pattern = '%${query.replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
    final rows = await raw.query(
      'notes',
      where: '''account_id = ? AND is_trash = 0 AND local_is_deleted = 0
        AND (title LIKE ? ESCAPE '\\' OR content LIKE ? ESCAPE '\\')''',
      whereArgs: [accountId, pattern, pattern],
      orderBy: 'updated_time DESC, server_id',
      limit: 100,
    );
    return rows.map(_noteFromRow).toList(growable: false);
  }

  Future<Note> createLocalNote({
    required Account account,
    required String notebookId,
    required bool isMarkdown,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final note = Note(
      noteId: _objectId(),
      notebookId: notebookId,
      userId: account.userId,
      title: '',
      content: '',
      tags: const [],
      usn: 0,
      isMarkdown: isMarkdown,
      isStarred: false,
      isTrash: false,
      isDeleted: false,
      createdTime: now,
      updatedTime: now,
    );
    await _writeNote(account.cacheKey, note, isDirty: true, isNew: true);
    return note;
  }

  Future<void> saveLocalNote(String accountId, Note note) =>
      _writeNote(accountId, note, isDirty: true, isNew: note.usn == 0);

  Future<void> restoreHistoryContent(
    String accountId,
    String noteId,
    String content,
  ) async {
    // Patch only the body of the latest cached row; the reader may hold an old
    // snapshot whose metadata or USN changed while the history was downloaded.
    final changed = await raw.update(
      'notes',
      {
        'content': content,
        'updated_time': DateTime.now().toUtc().toIso8601String(),
        'is_dirty': 1,
      },
      where: 'account_id = ? AND server_id = ? AND local_is_deleted = 0',
      whereArgs: [accountId, noteId],
    );
    if (changed != 1) throw StateError('localNoteMissing');
  }

  Future<List<Note>> dirtyNotes(String accountId) async {
    final rows = await raw.query(
      'notes',
      where: 'account_id = ? AND is_dirty = 1',
      whereArgs: [accountId],
      orderBy: 'created_time, server_id',
    );
    return rows.map(_noteFromRow).toList(growable: false);
  }

  Future<void> markNoteUploaded(
    String accountId,
    Note local,
    Note remote,
  ) async {
    if (remote.noteId != local.noteId || remote.usn <= 0) {
      throw StateError('invalidUploadResponse');
    }
    await raw.transaction((txn) async {
      final rows = await txn.query(
        'notes',
        where: 'account_id = ? AND server_id = ?',
        whereArgs: [accountId, local.noteId],
      );
      if (rows.isEmpty) throw StateError('localNoteMissing');
      final current = _noteFromRow(rows.single);
      final unchanged =
          current.title == local.title &&
          current.content == local.content &&
          current.notebookId == local.notebookId &&
          jsonEncode(current.tags) == jsonEncode(local.tags) &&
          current.isStarred == local.isStarred &&
          current.isTrash == local.isTrash &&
          current.isMarkdown == local.isMarkdown &&
          current.updatedTime == local.updatedTime;
      await txn.update(
        'notes',
        {
          'usn': remote.usn,
          'local_is_new': 0,
          'is_dirty': unchanged ? 0 : 1,
          if (unchanged && remote.updatedTime.isNotEmpty)
            'updated_time': remote.updatedTime,
        },
        where: 'account_id = ? AND server_id = ?',
        whereArgs: [accountId, local.noteId],
      );
    });
  }

  Future<void> _writeNote(
    String accountId,
    Note note, {
    required bool isDirty,
    required bool isNew,
  }) => raw.insert('notes', {
    'account_id': accountId,
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
    'is_dirty': isDirty ? 1 : 0,
    'local_is_new': isNew ? 1 : 0,
    'local_is_deleted': 0,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  static void _insertNote(Batch batch, String accountId, Note note) {
    batch.insert('notes', {
      'account_id': accountId,
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
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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

  static String _objectId() {
    final random = Random.secure();
    return List.generate(
      12,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

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
