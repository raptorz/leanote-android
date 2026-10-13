import 'dart:math';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../../domain/models/account.dart';
import '../../domain/models/attachment_upload.dart';

class PendingAttachment {
  const PendingAttachment({
    required this.id,
    required this.noteId,
    required this.name,
    required this.size,
    required this.state,
    required this.remoteId,
  });
  final String id, noteId, name, state, remoteId;
  final int size;
  String get statusLabel => switch (state) {
    'pending' => '待上传',
    'uncertain' => '上传结果待确认',
    'uploaded' => '已上传，本地副本保留',
    _ => '状态异常，请导出保留',
  };
}

/// User-owned originals, never part of the evictable download cache. Deliberately
/// no cascading FK: replacing a server snapshot must not delete unsent bytes.
class AttachmentOutbox {
  AttachmentOutbox(this.database, this.account);
  final Database database;
  final Account account;
  static const maxBytes = 64 * 1024 * 1024;
  static const maxItems = 64;
  static const schema = '''CREATE TABLE IF NOT EXISTS attachment_outbox (
    id TEXT PRIMARY KEY,
    account_id TEXT NOT NULL,
    note_id TEXT NOT NULL,
    name TEXT NOT NULL,
    bytes BLOB NOT NULL,
    state TEXT NOT NULL DEFAULT 'pending',
    remote_id TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL
  )''';

  Future<String> stage(String noteId, AttachmentUpload file) =>
      database.transaction((txn) async {
        final owner = await txn.query(
          'notes',
          columns: ['server_id'],
          where: 'account_id = ? AND server_id = ? AND owner_server_id = ? AND is_trash = 0 AND local_is_deleted = 0',
          whereArgs: [account.cacheKey, noteId, account.userId],
        );
        if (owner.isEmpty) throw StateError('不能向不存在或回收站中的笔记添加附件');
        final usage = (await txn.rawQuery(
          'SELECT COUNT(*) AS count, COALESCE(SUM(LENGTH(bytes)), 0) AS size FROM attachment_outbox',
        )).single;
        if ((usage['count'] as int) >= maxItems ||
            (usage['size'] as int) + file.bytes.length > maxBytes) {
          throw StateError('本地附件暂存已满（最多 64 个、合计 64 MiB），请先处理或导出已有附件');
        }
        final random = Random.secure();
        final id = List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
        await txn.insert('attachment_outbox', {
          'id': id,
          'account_id': account.cacheKey,
          'note_id': noteId,
          'name': file.name,
          'bytes': file.bytes,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        });
        return id;
      });

  Future<List<PendingAttachment>> list({String? noteId}) async {
    final rows = await database.query(
      'attachment_outbox',
      columns: [
        'id',
        'note_id',
        'name',
        'LENGTH(bytes) AS size',
        'state',
        'remote_id',
      ],
      where: 'account_id = ?${noteId == null ? '' : ' AND note_id = ?'}',
      whereArgs: [account.cacheKey, ?noteId],
      orderBy: 'created_at, id',
    );
    return rows
        .map(
          (r) => PendingAttachment(
            id: r['id'] as String,
            noteId: r['note_id'] as String,
            name: r['name'] as String,
            size: r['size'] as int,
            state: r['state'] as String,
            remoteId: r['remote_id'] as String,
          ),
        )
        .toList();
  }

  Future<AttachmentUpload> file(String id) async {
    final rows = await database.query(
      'attachment_outbox',
      where: 'account_id = ? AND id = ?',
      whereArgs: [account.cacheKey, id],
    );
    if (rows.isEmpty) throw StateError('本地附件不存在');
    return AttachmentUpload(
      name: rows.single['name'] as String,
      bytes: Uint8List.fromList(rows.single['bytes'] as List<int>),
    );
  }

  Future<void> markSending(String id) =>
      _transition(id, 'pending', 'uncertain');
  Future<void> confirm(String id, String remoteId) async {
    if (!RegExp(r'^[0-9a-fA-F]{24}$').hasMatch(remoteId)) {
      throw StateError('invalidAttachmentId');
    }
    await _transition(id, 'uncertain', 'uploaded', remoteId: remoteId);
  }

  /// Only after the user explicitly checks the server and accepts duplication risk.
  Future<void> retryUncertain(String id) =>
      _transition(id, 'uncertain', 'pending');

  Future<void> _transition(
    String id,
    String from,
    String to, {
    String remoteId = '',
  }) async {
    final count = await database.update(
      'attachment_outbox',
      {'state': to, 'remote_id': remoteId},
      where: 'account_id = ? AND id = ? AND state = ?',
      whereArgs: [account.cacheKey, id, from],
    );
    if (count != 1) throw StateError('附件任务状态已变化，请刷新');
  }

  Future<void> remove(String id) async {
    await database.delete(
      'attachment_outbox',
      where: 'account_id = ? AND id = ?',
      whereArgs: [account.cacheKey, id],
    );
  }
}
