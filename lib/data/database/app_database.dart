import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/models/account.dart';
import '../../domain/models/note.dart';
import '../../domain/models/note_file.dart';
import '../../domain/models/note_history.dart';
import '../../domain/models/notebook.dart';
import '../../domain/models/shared_note.dart';

class AppDatabase {
  AppDatabase._(this.raw);

  static const schemaVersion = 5;
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
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) await db.execute(_historySchema);
        if (oldVersion < 3) await db.execute(_avatarSchema);
        if (oldVersion < 4) await db.execute(_sharedSchema);
        if (oldVersion < 5) await db.execute(_fileCacheSchema);
      },
    );
    return AppDatabase._(database);
  }

  Future<void> replaceNoteFiles(
    String accountId,
    String noteId,
    List<NoteFile> files,
  ) => raw.transaction((txn) async {
    final generation = _objectId();
    await txn.delete(
      'note_files',
      where: 'account_id = ? AND note_id = ?',
      whereArgs: [accountId, noteId],
    );
    for (final file in files) {
      await txn.insert('note_files', {
        'account_id': accountId,
        'note_id': noteId,
        'file_id': file.id,
        'title': file.title,
        'type': file.type,
        'is_attachment': file.isAttachment ? 1 : 0,
        'generation': generation,
      });
    }
  });

  Future<List<NoteFile>> cachedNoteFiles(
    String accountId,
    String noteId,
  ) async {
    final rows = await raw.query(
      'note_files',
      where: 'account_id = ? AND note_id = ?',
      whereArgs: [accountId, noteId],
      orderBy: 'title, file_id',
    );
    return rows
        .map(
          (row) => NoteFile(
            id: row['file_id'] as String,
            title: row['title'] as String,
            type: row['type'] as String,
            isAttachment: row['is_attachment'] == 1,
            cacheGeneration: row['generation'] as String,
          ),
        )
        .toList();
  }

  Future<Uint8List> cachedNoteImage(
    String accountId,
    String noteId,
    NoteFile file,
  ) => _cachedNoteFile(accountId, noteId, file, false);

  Future<Uint8List> cachedNoteAttachment(
    String accountId,
    String noteId,
    NoteFile file,
  ) => _cachedNoteFile(accountId, noteId, file, true);

  Future<Uint8List> _cachedNoteFile(
    String accountId,
    String noteId,
    NoteFile file,
    bool attachment,
  ) async {
    final rows = await raw.query(
      'note_files',
      columns: ['bytes'],
      where: 'account_id = ? AND note_id = ? AND file_id = ? AND generation = ? AND is_attachment = ?',
      whereArgs: [
        accountId,
        noteId,
        file.id,
        file.cacheGeneration,
        attachment ? 1 : 0,
      ],
    );
    if (rows.isEmpty || rows.single['bytes'] == null) {
      throw StateError('文件尚未缓存或缓存已失效，请联网下载');
    }
    return rows.single['bytes'] as Uint8List;
  }

  Future<void> cacheNoteImage(
    String accountId,
    String noteId,
    NoteFile file,
    Uint8List bytes,
  ) => _cacheNoteFile(accountId, noteId, file, bytes, false);

  Future<void> cacheNoteAttachment(
    String accountId,
    String noteId,
    NoteFile file,
    Uint8List bytes,
  ) => _cacheNoteFile(accountId, noteId, file, bytes, true);

  Future<void> _cacheNoteFile(
    String accountId,
    String noteId,
    NoteFile file,
    Uint8List bytes,
    bool attachment,
  ) => raw.transaction((txn) async {
    if ((!attachment && bytes.isEmpty) ||
        bytes.length > (attachment ? 32 : 8) * 1024 * 1024) {
      throw StateError('invalidFileSize');
    }
    final changed = await txn.update(
      'note_files',
      {'bytes': bytes, 'cached_at': DateTime.now().microsecondsSinceEpoch},
      where: 'account_id = ? AND note_id = ? AND file_id = ? AND generation = ? AND is_attachment = ?',
      whereArgs: [
        accountId,
        noteId,
        file.id,
        file.cacheGeneration,
        attachment ? 1 : 0,
      ],
    );
    if (changed != 1) throw StateError('文件列表已变化，请刷新后重试');
    // Bound binary data across all accounts. Eviction never deletes note text.
    final rows = await txn.rawQuery(
      'SELECT rowid, length(bytes) AS size FROM note_files WHERE bytes IS NOT NULL ORDER BY cached_at DESC, rowid DESC',
    );
    var total = 0;
    for (final row in rows) {
      total += row['size'] as int;
      if (total > 64 * 1024 * 1024) {
        await txn.update(
          'note_files',
          {'bytes': null},
          where: 'rowid = ?',
          whereArgs: [row['rowid']],
        );
      }
    }
  });

  Future<void> replaceSharedSnapshot(
    String accountId,
    List<SharedNote> notes,
  ) => raw.transaction((txn) async {
    final previous = await txn.query(
      'shared_notes',
      where: 'account_id = ?',
      whereArgs: [accountId],
    );
    final old = {for (final row in previous) row['note_id']: row};
    await txn.delete(
      'shared_notes',
      where: 'account_id = ?',
      whereArgs: [accountId],
    );
    for (final shared in notes) {
      final existing = old[shared.note.noteId];
      await txn.insert('shared_notes', {
        'account_id': accountId,
        'note_id': shared.note.noteId,
        'owner_id': shared.note.userId,
        'version': shared.version,
        'metadata': jsonEncode(shared.toJson()),
        'content':
            existing != null &&
                existing['version'] == shared.version &&
                existing['owner_id'] == shared.note.userId
            ? existing['content']
            : null,
      });
    }
  });

  Future<List<SharedNote>> cachedSharedNotes(String accountId) async {
    final rows = await raw.query(
      'shared_notes',
      where: 'account_id = ?',
      whereArgs: [accountId],
      orderBy: 'note_id',
    );
    final result = rows
        .map(
          (row) => SharedNote.fromJson(
            Map<String, Object?>.from(
              jsonDecode(row['metadata'] as String) as Map,
            ),
          ),
        )
        .toList();
    result.sort((a, b) {
      final cmp = a.note.title.toLowerCase().compareTo(
        b.note.title.toLowerCase(),
      );
      return cmp == 0 ? a.note.noteId.compareTo(b.note.noteId) : cmp;
    });
    return result;
  }

  Future<void> cacheSharedContent(
    String accountId,
    SharedNote note,
    String content,
  ) async {
    final changed = await raw.update(
      'shared_notes',
      {'content': content},
      where: 'account_id = ? AND note_id = ? AND owner_id = ? AND version = ?',
      whereArgs: [accountId, note.note.noteId, note.note.userId, note.version],
    );
    if (changed != 1) throw StateError('共享列表已变化，请刷新后重试');
  }

  Future<Note> cachedSharedContent(String accountId, SharedNote note) async {
    final rows = await raw.query(
      'shared_notes',
      where: 'account_id = ? AND note_id = ? AND owner_id = ? AND version = ?',
      whereArgs: [accountId, note.note.noteId, note.note.userId, note.version],
    );
    if (rows.isEmpty || rows.single['content'] == null) {
      throw StateError('此共享正文尚未缓存或已失效，请联网刷新后查看');
    }
    final current = SharedNote.fromJson(
      Map<String, Object?>.from(
        jsonDecode(rows.single['metadata'] as String) as Map,
      ),
    );
    return current.note.copyWith(content: rows.single['content'] as String);
  }

  Future<void> removeSharedNote(String accountId, String noteId) async {
    await raw.delete(
      'shared_notes',
      where: 'account_id = ? AND note_id = ?',
      whereArgs: [accountId, noteId],
    );
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

  Future<Uint8List?> cachedAvatar(String accountId) async {
    final rows = await raw.query(
      'account_avatars',
      columns: ['bytes'],
      where: 'account_id = ?',
      whereArgs: [accountId],
    );
    return rows.isEmpty ? null : rows.single['bytes'] as Uint8List;
  }

  Future<void> cacheAvatar(String accountId, Uint8List? bytes) async {
    if (bytes == null) {
      await raw.delete(
        'account_avatars',
        where: 'account_id = ?',
        whereArgs: [accountId],
      );
    } else {
      await raw.insert('account_avatars', {
        'account_id': accountId,
        'bytes': bytes,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
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

  Future<String> noteSnapshotFingerprint(String accountId) async => jsonEncode(
    await raw.query(
      'notes',
      where: 'account_id = ?',
      whereArgs: [accountId],
      orderBy: 'server_id',
    ),
  );

  Future<void> replaceSnapshot({
    required Account account,
    required List<Notebook> notebooks,
    required List<Note> notes,
    required List<Map<String, Object?>> tags,
    required int lastSyncUsn,
    String? expectedNoteSnapshot,
  }) async {
    await raw.transaction((txn) async {
      final pending = await txn.query(
        'notes',
        columns: ['server_id'],
        where: 'account_id = ? AND is_dirty = 1',
        whereArgs: [account.cacheKey],
        limit: 1,
      );
      if (expectedNoteSnapshot == null) {
        if (pending.isNotEmpty) throw StateError('unsyncedChanges');
      } else {
        final current = jsonEncode(
          await txn.query(
            'notes',
            where: 'account_id = ?',
            whereArgs: [account.cacheKey],
            orderBy: 'server_id',
          ),
        );
        if (current != expectedNoteSnapshot) {
          throw StateError('localChangesDuringReset');
        }
      }
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
            'note_histories',
            where: 'account_id = ? AND note_id = ?',
            whereArgs: [account.cacheKey, note.noteId],
          );
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

  Future<Map<String, int>> tagCounts(String accountId) async {
    final rows = await raw.query(
      'notes',
      columns: ['tags_json'],
      where: 'account_id = ? AND is_trash = 0 AND local_is_deleted = 0',
      whereArgs: [accountId],
    );
    final counts = <String, int>{};
    for (final row in rows) {
      final tags = (jsonDecode(row['tags_json'] as String) as List)
          .cast<String>()
          .where((tag) => tag.trim().isNotEmpty)
          .toSet();
      for (final tag in tags) {
        counts.update(tag, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    final names = counts.keys.toList()
      ..sort((a, b) {
        final order = a.toLowerCase().compareTo(b.toLowerCase());
        return order == 0 ? a.compareTo(b) : order;
      });
    return {for (final name in names) name: counts[name]!};
  }

  Future<List<Note>> notesForTag(String accountId, String tag) async {
    if (tag.trim().isEmpty) return [];
    return (await notes(accountId))
        .where((note) => note.tags.contains(tag))
        .toList(growable: false);
  }

  Future<List<Note>> notes(
    String accountId, {
    String? notebookId,
    bool starredOnly = false,
    bool trashOnly = false,
  }) async {
    final clauses = <String>[
      'account_id = ?',
      'local_is_deleted = 0',
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

  Future<List<Note>> searchNotes(
    String accountId,
    String query, {
    int limit = 50,
  }) async {
    if (limit < 1) throw ArgumentError.value(limit, 'limit');
    final escaped = query
        .replaceAll('\\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final pattern = '%$escaped%';
    final rows = await raw.query(
      'notes',
      where: '''account_id = ? AND is_trash = 0 AND local_is_deleted = 0
        AND (title LIKE ? ESCAPE '\\' OR content LIKE ? ESCAPE '\\')''',
      whereArgs: [accountId, pattern, pattern],
      orderBy: 'updated_time DESC, server_id',
      limit: limit,
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

  Future<void> saveNoteTags(
    String accountId,
    String noteId,
    List<String> tags,
  ) => raw.transaction((txn) async {
    final normalized = tags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList();
    final rows = await txn.query(
      'notes',
      where: 'account_id = ? AND server_id = ? AND local_is_deleted = 0',
      whereArgs: [accountId, noteId],
    );
    if (rows.isEmpty) throw StateError('localNoteMissing');
    final current = _noteFromRow(rows.single);
    if (jsonEncode(current.tags) == jsonEncode(normalized)) return;
    // Also guard new notes: an add request may already be in flight.
    if (normalized.isEmpty) {
      throw const FormatException('当前服务端接口不支持清空全部标签，请至少保留一个标签');
    }
    await txn.update(
      'notes',
      {
        'tags_json': jsonEncode(normalized),
        'is_dirty': 1,
        'updated_time': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'account_id = ? AND server_id = ?',
      whereArgs: [accountId, noteId],
    );
  });

  Future<void> saveEditedText(
    String accountId,
    String noteId,
    String title,
    String content,
  ) => raw.transaction((txn) async {
    final rows = await txn.query(
      'notes',
      columns: ['title', 'content'],
      where: 'account_id = ? AND server_id = ? AND local_is_deleted = 0',
      whereArgs: [accountId, noteId],
    );
    if (rows.isEmpty) throw StateError('localNoteMissing');
    if (rows.single['title'] == title && rows.single['content'] == content) {
      return;
    }
    await txn.update(
      'notes',
      {
        'title': title,
        'content': content,
        'updated_time': DateTime.now().toUtc().toIso8601String(),
        'is_dirty': 1,
      },
      where: 'account_id = ? AND server_id = ?',
      whereArgs: [accountId, noteId],
    );
  });

  Future<void> saveLocalNote(String accountId, Note note) async {
    final changed = await raw.update(
      'notes',
      {
        'notebook_server_id': note.notebookId,
        'title': note.title,
        'content': note.content,
        'tags_json': jsonEncode(note.tags),
        'is_markdown': note.isMarkdown ? 1 : 0,
        'is_starred': note.isStarred ? 1 : 0,
        'is_trash': note.isTrash ? 1 : 0,
        'updated_time': note.updatedTime,
        'is_dirty': 1,
      },
      where: 'account_id = ? AND server_id = ? AND local_is_deleted = 0',
      whereArgs: [accountId, note.noteId],
    );
    if (changed != 1) throw StateError('localNoteMissing');
  }

  Future<void> deleteLocalTrash(String accountId, String noteId) async {
    final changed = await raw.update(
      'notes',
      {'local_is_deleted': 1, 'is_dirty': 1},
      where: 'account_id = ? AND server_id = ? AND is_trash = 1 AND local_is_deleted = 0',
      whereArgs: [accountId, noteId],
    );
    if (changed != 1) throw StateError('trashNoteMissing');
  }

  Future<void> acknowledgeDeletion(String accountId, Note note) =>
      raw.transaction((txn) async {
        final changed = await txn.delete(
          'notes',
          where: 'account_id = ? AND server_id = ? AND local_is_deleted = 1 AND usn = ?',
          whereArgs: [accountId, note.noteId, note.usn],
        );
        if (changed != 1) throw StateError('localChangesDuringDeletion');
        await txn.delete(
          'note_histories',
          where: 'account_id = ? AND note_id = ?',
          whereArgs: [accountId, note.noteId],
        );
      });

  Future<void> _requireLiveNote(
    DatabaseExecutor db,
    String accountId,
    String noteId,
  ) async {
    final rows = await db.query(
      'notes',
      columns: ['server_id'],
      where: 'account_id = ? AND server_id = ? AND local_is_deleted = 0',
      whereArgs: [accountId, noteId],
    );
    if (rows.isEmpty) throw StateError('localNoteMissing');
  }

  Future<void> cacheHistories(
    String accountId,
    String noteId,
    List<NoteHistory> histories,
  ) => raw.transaction((txn) async {
    await _requireLiveNote(txn, accountId, noteId);
    final old = await txn.query(
      'note_histories',
      where: 'account_id = ? AND note_id = ?',
      whereArgs: [accountId, noteId],
    );
    final bodies = {for (final row in old) row['history_id']: row['content']};
    await txn.delete(
      'note_histories',
      where: 'account_id = ? AND note_id = ?',
      whereArgs: [accountId, noteId],
    );
    for (final history in histories) {
      await txn.insert('note_histories', {
        'account_id': accountId,
        'note_id': noteId,
        'history_id': history.id,
        'updated_time': history.updatedTime,
        'updated_user_id': history.updatedUserId,
        'content': bodies[history.id],
      });
    }
  });

  Future<List<NoteHistory>> cachedHistories(String accountId, String noteId) =>
      raw.transaction((txn) async {
        await _requireLiveNote(txn, accountId, noteId);
        final rows = await txn.query(
          'note_histories',
          where: 'account_id = ? AND note_id = ?',
          whereArgs: [accountId, noteId],
          orderBy: 'updated_time DESC, history_id',
        );
        return rows
            .map(
              (row) => NoteHistory(
                id: row['history_id'] as String,
                updatedTime: row['updated_time'] as String,
                updatedUserId: row['updated_user_id'] as String,
              ),
            )
            .toList();
      });

  Future<void> cacheHistoryContent(
    String accountId,
    String noteId,
    String historyId,
    String content,
  ) => raw.transaction((txn) async {
    await _requireLiveNote(txn, accountId, noteId);
    // The list may have been refreshed while this body was downloading.
    final count = await txn.update(
      'note_histories',
      {'content': content},
      where: 'account_id = ? AND note_id = ? AND history_id = ?',
      whereArgs: [accountId, noteId, historyId],
    );
    if (count != 1) throw StateError('historyNotListed');
  });

  Future<String> cachedHistoryContent(
    String accountId,
    String noteId,
    String historyId,
  ) => raw.transaction((txn) async {
    await _requireLiveNote(txn, accountId, noteId);
    final rows = await txn.query(
      'note_histories',
      columns: ['content'],
      where: 'account_id = ? AND note_id = ? AND history_id = ?',
      whereArgs: [accountId, noteId, historyId],
    );
    if (rows.isEmpty || rows.single['content'] == null) {
      throw StateError('此历史正文尚未缓存，请联网查看后再离线使用');
    }
    return rows.single['content'] as String;
  });

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

  Future<Set<String>> pendingNoteIds(String accountId) async {
    final rows = await raw.query(
      'notes',
      columns: ['server_id'],
      where: 'account_id = ? AND is_dirty = 1',
      whereArgs: [accountId],
    );
    return rows.map((row) => row['server_id'] as String).toSet();
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

  /// Atomically preserve a safe local body copy before accepting the remote note.
  /// Unsupported resource/format conflicts and concurrent edits remain dirty.
  Future<Note?> resolveNoteConflict(
    String accountId,
    Note local,
    Note remote, {
    required bool filesConfirmedEmpty,
  }) => raw.transaction((txn) async {
    if (remote.noteId != local.noteId ||
        remote.userId != local.userId ||
        remote.usn <= local.usn ||
        local.usn <= 0 ||
        remote.isDeleted ||
        local.isDeleted ||
        remote.isMarkdown != local.isMarkdown ||
        remote.isTrash != local.isTrash) {
      throw StateError('unresolvedNoteConflict');
    }
    final rows = await txn.query(
      'notes',
      where: 'account_id = ? AND server_id = ? AND is_dirty = 1',
      whereArgs: [accountId, local.noteId],
    );
    if (rows.length != 1 ||
        _noteFingerprint(_noteFromRow(rows.single)) !=
            _noteFingerprint(local)) {
      throw StateError('localChangesDuringConflict');
    }
    Note? copy;
    if (remote.content != local.content) {
      // Conservative until resource cloning exists: brackets/HTML may encode
      // images, reference links or embedded media, including legacy URLs.
      final markup = RegExp(r'[\[<]');
      final files = await txn.query(
        'note_files',
        columns: ['file_id'],
        where: 'account_id = ? AND note_id = ?',
        whereArgs: [accountId, local.noteId],
        limit: 1,
      );
      if (!filesConfirmedEmpty ||
          !local.isMarkdown ||
          local.isTrash ||
          markup.hasMatch(local.content) ||
          markup.hasMatch(remote.content) ||
          files.isNotEmpty) {
        throw StateError('unresolvedNoteConflict');
      }
      final now = DateTime.now().toUtc().toIso8601String();
      copy = local.copyWith(
        noteId: _objectId(),
        title: '${local.title}（本地冲突副本）',
        usn: 0,
        createdTime: now,
        updatedTime: now,
      );
    }
    final batch = txn.batch();
    if (copy != null) {
      _insertNote(batch, accountId, copy);
      batch.update(
        'notes',
        {'is_dirty': 1, 'local_is_new': 1},
        where: 'account_id = ? AND server_id = ?',
        whereArgs: [accountId, copy.noteId],
      );
    }
    _insertNote(batch, accountId, remote);
    await batch.commit(noResult: true);
    // Do not advance the account cursor: other remote changes are still unread.
    return copy;
  });

  static String _noteFingerprint(Note note) => jsonEncode([
    note.noteId,
    note.userId,
    note.notebookId,
    note.title,
    note.content,
    note.tags,
    note.usn,
    note.isMarkdown,
    note.isStarred,
    note.isTrash,
    note.isDeleted,
    note.createdTime,
    note.updatedTime,
  ]);

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
          current.isDeleted == local.isDeleted &&
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
    isDeleted: row['local_is_deleted'] == 1,
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

  static const _historySchema = '''CREATE TABLE note_histories (
    account_id TEXT NOT NULL,
    note_id TEXT NOT NULL,
    history_id TEXT NOT NULL,
    updated_time TEXT NOT NULL,
    updated_user_id TEXT NOT NULL,
    content TEXT,
    PRIMARY KEY (account_id, note_id, history_id),
    FOREIGN KEY (account_id) REFERENCES accounts(account_id) ON DELETE CASCADE
  )''';

  static const _avatarSchema = '''CREATE TABLE account_avatars (
    account_id TEXT PRIMARY KEY,
    bytes BLOB NOT NULL,
    FOREIGN KEY (account_id) REFERENCES accounts(account_id) ON DELETE CASCADE
  )''';

  static const _sharedSchema = '''CREATE TABLE shared_notes (
    account_id TEXT NOT NULL, note_id TEXT NOT NULL, owner_id TEXT NOT NULL,
    version TEXT NOT NULL, metadata TEXT NOT NULL, content TEXT,
    PRIMARY KEY (account_id, note_id),
    FOREIGN KEY (account_id) REFERENCES accounts(account_id) ON DELETE CASCADE
  )''';

  static const _fileCacheSchema = '''CREATE TABLE note_files (
    account_id TEXT NOT NULL, note_id TEXT NOT NULL, file_id TEXT NOT NULL,
    title TEXT NOT NULL, type TEXT NOT NULL, is_attachment INTEGER NOT NULL,
    generation TEXT NOT NULL, bytes BLOB, cached_at INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (account_id, note_id, file_id),
    FOREIGN KEY (account_id, note_id) REFERENCES notes(account_id, server_id) ON DELETE CASCADE
  )''';

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
    _historySchema,
    _avatarSchema,
    _sharedSchema,
    _fileCacheSchema,
  ];
}
