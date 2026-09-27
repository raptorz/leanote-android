import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gemsnote/core/api/api2_client.dart';
import 'package:gemsnote/data/database/app_database.dart';
import 'package:gemsnote/data/session/session_store.dart';
import 'package:gemsnote/domain/models/account.dart';
import 'package:gemsnote/repositories/auth_repository.dart';
import 'package:gemsnote/sync/sync_coordinator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MemorySessions implements SessionStore {
  final values = <String, String>{};
  @override
  Future<void> write(String userId, String token) async {
    values[userId] = token;
  }

  @override
  Future<String?> read(String userId) async => values[userId];
  @override
  Future<void> delete(String userId) async {
    values.remove(userId);
  }
}

void main() {
  test(
    'login with renamed user preserves dirty cache without downloading',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final db = await AppDatabase.open(databasePath: inMemoryDatabasePath);
      addTearDown(db.raw.close);
      final account = Account(
        userId: '507f1f77bcf86cd799439011',
        server: Uri.parse('https://notes.example.test/'),
        username: 'old',
        email: 'user@example.test',
        logo: '',
      );
      await db.replaceSnapshot(
        account: account,
        notebooks: [],
        notes: [],
        tags: [],
        lastSyncUsn: 9,
      );
      final draft = await db.createLocalNote(
        account: account,
        notebookId: '507f1f77bcf86cd799439012',
        isMarkdown: true,
      );
      await db.saveLocalNote(
        account.cacheKey,
        draft.copyWith(content: 'Offline work'),
      );
      await db.deactivate(account.cacheKey);
      final requests = <String>[];
      final api = Api2Client(
        httpClient: MockClient((request) async {
          requests.add(request.url.path);
          expect(request.url.path, '/api2/auth/login');
          return http.Response(
            jsonEncode({
              'Ok': true,
              'Token': 'fresh-token',
              'User': {
                'UserId': account.userId,
                'Username': 'renamed',
                'Email': account.email,
                'Logo': '',
              },
              'Server': {
                'Name': 'gemsnote',
                'Version': '1.0.0',
                'MinVersion': '',
              },
            }),
            200,
          );
        }),
      );
      final sessions = MemorySessions();
      final repository = AuthRepository(
        api,
        db,
        sessions,
        SyncCoordinator(api, db),
      );
      await repository.loginAndDownload(
        serverAddress: account.server.toString(),
        identity: 'renamed',
        password: 'test-password',
      );
      expect(requests, ['/api2/auth/login']);
      expect(
        (await db.dirtyNotes(account.cacheKey)).single.content,
        'Offline work',
      );
      expect(await db.lastSyncUsn(account.cacheKey), 9);
      expect((await repository.restore())?.account.username, 'renamed');
      expect((await repository.restore())?.token, 'fresh-token');
    },
  );
}
