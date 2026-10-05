import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'dart:io' show Cookie;

import 'package:http/http.dart' as http;

import '../../domain/models/account.dart';
import '../../domain/models/note.dart';
import '../../domain/models/note_file.dart';
import '../../domain/models/note_history.dart';
import '../../domain/models/notebook.dart';
import '../../domain/models/shared_note.dart';
import 'api_exception.dart';

class LoginResult {
  const LoginResult({
    required this.token,
    required this.account,
    required this.serverVersion,
    required this.minimumClientVersion,
  });

  final String token;
  final Account account;
  final String serverVersion;
  final String minimumClientVersion;
}

class Api2Client {
  Api2Client({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  static const clientVersion = '1.0.0';
  final http.Client _http;

  /// Operation-local browser session; never persist cookies or passwords.
  Future<void> updateUsername({
    required Uri server,
    required String userId,
    required String identity,
    required String password,
    required String username,
  }) => _accountFormAction(
    server: server,
    userId: userId,
    identity: identity,
    password: password,
    path: '/api2/user/updateUsername',
    fields: {'username': username},
  );

  Future<void> requestEmailChange({
    required Uri server,
    required String userId,
    required String identity,
    required String password,
    required String email,
  }) => _accountFormAction(
    server: server,
    userId: userId,
    identity: identity,
    password: password,
    path: '/api2/web/emailChange',
    fields: {'email': email, 'pwd': password},
  );

  Future<void> changePassword({
    required Uri server,
    required String userId,
    required String identity,
    required String oldPassword,
    required String password,
  }) => _accountFormAction(
    server: server,
    userId: userId,
    identity: identity,
    password: oldPassword,
    path: '/api2/user/updatePwd',
    fields: {'oldPwd': oldPassword, 'pwd': password},
  );

  Future<void> _accountFormAction({
    required Uri server,
    required String userId,
    required String identity,
    required String password,
    required String path,
    required Map<String, String> fields,
  }) async {
    final cookies = <String, String>{};
    Future<Map<String, Object?>> call(
      String path, {
      Map<String, String>? body,
      bool form = false,
    }) async {
      final request = http.Request(
        body == null ? 'GET' : 'POST',
        server.resolve(path),
      )..followRedirects = false;
      if (cookies.isNotEmpty) {
        request.headers['Cookie'] = cookies.entries
            .map((e) => '${e.key}=${e.value}')
            .join('; ');
      }
      if (body != null) {
        if (form) {
          request.bodyFields = body;
        } else {
          request.headers['Content-Type'] = 'application/json';
          request.body = jsonEncode(body);
        }
      }
      late http.Response response;
      try {
        response = await (() async => http.Response.fromStream(
          await _http.send(request),
        ))().timeout(const Duration(seconds: 60));
      } on Exception {
        throw const ApiException('networkUnavailable');
      }
      final header = response.headers['set-cookie'];
      if (header != null) {
        // Split combined cookie fields, but not commas within Expires dates.
        for (final part in header.split(RegExp(r',(?=\s*[^\s;,=]+=)'))) {
          try {
            final cookie = Cookie.fromSetCookieValue(part.trim());
            cookies[cookie.name] = cookie.value;
          } on FormatException {
            throw const ApiException('invalidSessionCookie');
          }
        }
      }
      return _decodeMapResponse(response);
    }

    try {
      final login = await call(
        '/api2/auth/session',
        body: {'email': identity, 'pwd': password},
      );
      if (login['Ok'] != true || cookies.isEmpty) {
        throw const ApiException('invalidSession');
      }
      final bootstrap = await call('/api2/bootstrap');
      final user = bootstrap['User'];
      if (bootstrap['Ok'] != true || user is! Map || user['UserId'] != userId) {
        throw const ApiException('accountMismatch');
      }
      final result = await call(
        path,
        body: fields,
        form: true, // This API2 v1 action still uses Revel form binding, like Web.
      );
      if (result['Ok'] != true) throw const ApiException('invalidResponse');
    } finally {
      if (cookies.isNotEmpty) {
        try {
          await call(
            '/api2/logout',
            body: {},
          ).timeout(const Duration(seconds: 5));
        } on Object {
          /* best effort; do not retry a mutation */
        }
      }
      cookies.clear();
    }
  }

  Future<List<NoteFile>> noteFiles({
    required Uri server,
    required String token,
    required String noteId,
    required String userId,
  }) async {
    final data = await _requestJson(
      server: server,
      path: '/api2/note/getNote',
      method: 'GET',
      token: token,
      query: {'noteId': noteId},
    );
    if (data['NoteId'] != noteId ||
        data['UserId'] != userId ||
        !data.containsKey('Files') ||
        (data['Files'] != null && data['Files'] is! List)) {
      throw const ApiException('invalidResponse');
    }
    if (data['IsDeleted'] == true) throw const ApiException('notExists');
    final result = <NoteFile>[];
    final ids = <String>{};
    try {
      for (final item in data['Files'] as List? ?? []) {
        final file = NoteFile.fromJson(_map(item));
        if (!ids.add(file.id)) throw const FormatException('duplicateFile');
        result.add(file);
      }
    } on FormatException {
      throw const ApiException('invalidResponse');
    }
    return result;
  }

  Future<Uint8List> noteImage({
    required Uri server,
    required String token,
    required String noteId,
    required String userId,
    required NoteFile file,
  }) async {
    // Recheck membership rather than trusting an old list or a body-supplied URL.
    final files = await noteFiles(
      server: server,
      token: token,
      noteId: noteId,
      userId: userId,
    );
    if (file.isAttachment ||
        !files.any((item) => item.id == file.id && !item.isAttachment)) {
      throw const ApiException('imageNotInNote');
    }
    final request = http.Request(
      'GET',
      _uri(
        server,
        '/api2/file/getImage',
        token: token,
        query: {'fileId': file.id},
      ),
    )..followRedirects = false;
    try {
      final response = await _http
          .send(request)
          .timeout(const Duration(seconds: 15));
      const maxBytes = 8 * 1024 * 1024;
      if (response.statusCode != 200 ||
          (response.contentLength ?? 0) > maxBytes ||
          !{'image/png', 'image/jpeg', 'image/gif', 'image/webp'}.contains(
            response.headers['content-type']
                ?.split(';')
                .first
                .trim()
                .toLowerCase(),
          )) {
        await response.stream.listen((_) {}).cancel();
        throw const ApiException('invalidImageResponse');
      }
      final bytes = BytesBuilder(copy: false);
      final chunks = StreamIterator(response.stream);
      final timer = Stopwatch()..start();
      try {
        while (await chunks.moveNext().timeout(
          const Duration(seconds: 15) - timer.elapsed,
        )) {
          if (bytes.length + chunks.current.length > maxBytes) {
            throw const ApiException('imageTooLarge');
          }
          bytes.add(chunks.current);
        }
      } finally {
        await chunks.cancel();
      }
      if (bytes.isEmpty) throw const ApiException('invalidImageResponse');
      return bytes.takeBytes();
    } on ApiException {
      rethrow;
    } on Exception {
      throw const ApiException('imageDownloadFailed');
    }
  }

  Future<Uint8List> noteAttachment({
    required Uri server,
    required String token,
    required String noteId,
    required String userId,
    required NoteFile file,
  }) async {
    final files = await noteFiles(
      server: server,
      token: token,
      noteId: noteId,
      userId: userId,
    );
    if (!file.isAttachment ||
        !files.any((item) => item.id == file.id && item.isAttachment)) {
      throw const ApiException('attachmentNotInNote');
    }
    final request = http.Request(
      'GET',
      _uri(
        server,
        '/api2/file/getAttach',
        token: token,
        query: {'fileId': file.id},
      ),
    )..followRedirects = false;
    try {
      final response = await _http
          .send(request)
          .timeout(const Duration(seconds: 30));
      const maxBytes = 32 * 1024 * 1024;
      // This endpoint also returns HTTP 200 for errors. Only an actual download
      // has Content-Disposition: attachment; never save an error/login response.
      if (response.statusCode != 200 ||
          (response.contentLength ?? 0) > maxBytes ||
          response.headers['content-disposition']
                  ?.split(';')
                  .first
                  .trim()
                  .toLowerCase() !=
              'attachment') {
        await response.stream.listen((_) {}).cancel();
        throw const ApiException('invalidAttachmentResponse');
      }
      final bytes = BytesBuilder(copy: false);
      final chunks = StreamIterator(response.stream);
      final timer = Stopwatch()..start();
      try {
        while (await chunks.moveNext().timeout(
          const Duration(seconds: 60) - timer.elapsed,
        )) {
          if (bytes.length + chunks.current.length > maxBytes) {
            throw const ApiException('attachmentTooLarge');
          }
          bytes.add(chunks.current);
        }
      } finally {
        await chunks.cancel();
      }
      // Empty files are valid attachments, unlike images.
      return bytes.takeBytes();
    } on ApiException {
      rethrow;
    } on Exception {
      throw const ApiException('attachmentDownloadFailed');
    }
  }

  Future<Uint8List?> downloadAvatar({
    required Uri server,
    required String logo,
  }) async {
    if (logo.trim().isEmpty) return null;
    final uri = server.resolve(logo);
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.origin != server.origin ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const ApiException('invalidAvatarUrl');
    }
    // Public static resource: no token, cookies or automatic redirects.
    final request = http.Request('GET', uri)..followRedirects = false;
    try {
      final response = await _http
          .send(request)
          .timeout(const Duration(seconds: 15));
      const maxBytes = 2 * 1024 * 1024;
      if (response.statusCode != 200 ||
          (response.contentLength ?? 0) > maxBytes ||
          !['image/png', 'image/jpeg', 'image/gif', 'image/webp'].contains(
            response.headers['content-type']
                ?.split(';')
                .first
                .trim()
                .toLowerCase(),
          )) {
        await response.stream.listen((_) {}).cancel();
        throw const ApiException('invalidAvatarResponse');
      }
      final bytes = BytesBuilder(copy: false);
      final chunks = StreamIterator(response.stream);
      final timer = Stopwatch()..start();
      try {
        while (await chunks.moveNext().timeout(
          const Duration(seconds: 15) - timer.elapsed,
        )) {
          final chunk = chunks.current;
          if (bytes.length + chunk.length > maxBytes) {
            throw const ApiException('avatarTooLarge');
          }
          bytes.add(chunk);
        }
      } finally {
        await chunks.cancel();
      }
      if (bytes.isEmpty) throw const ApiException('invalidAvatarResponse');
      return bytes.takeBytes();
    } on ApiException {
      rethrow;
    } on Exception {
      throw const ApiException('avatarDownloadFailed');
    }
  }

  Future<LoginResult> login({
    required Uri server,
    required String identity,
    required String password,
  }) async {
    final data = await _requestJson(
      server: server,
      path: '/api2/auth/login',
      method: 'POST',
      body: <String, Object?>{'email': identity, 'pwd': password},
    );
    final token = _string(data, 'Token');
    final user = _map(data['User']);
    final version = _map(data['Server']);
    if (_string(version, 'Name').toLowerCase() != 'gemsnote') {
      throw const ApiException('serverMigrationRequired');
    }
    return LoginResult(
      token: token,
      account: Account.fromJson(user, server: server),
      serverVersion: _string(version, 'Version'),
      minimumClientVersion: version['MinVersion']?.toString() ?? '',
    );
  }

  Future<int> getSyncUsn({required Uri server, required String token}) async {
    final data = await _requestJson(
      server: server,
      path: '/api2/user/getSyncState',
      method: 'GET',
      token: token,
    );
    final value = data['LastSyncUsn'];
    if (value is! int || value < 0) {
      throw const ApiException('invalidSyncState');
    }
    return value;
  }

  Future<List<Notebook>> getNotebooks({
    required Uri server,
    required String token,
    required int afterUsn,
    int maxEntry = 100,
  }) async {
    final data = await _requestList(
      server: server,
      path: '/api2/notebook/getSyncNotebooks',
      token: token,
      query: {'afterUsn': '$afterUsn', 'maxEntry': '$maxEntry'},
    );
    return data.map(Notebook.fromJson).toList(growable: false);
  }

  Future<List<Note>> getNotesWithContent({
    required Uri server,
    required String token,
    required int afterUsn,
    int maxEntry = 50,
  }) async {
    final data = await _requestList(
      server: server,
      path: '/api2/note/getSyncNotesWithContent',
      token: token,
      query: {'afterUsn': '$afterUsn', 'maxEntry': '$maxEntry'},
    );
    return data.map(Note.fromJson).toList(growable: false);
  }

  Future<List<Map<String, Object?>>> getTags({
    required Uri server,
    required String token,
    required int afterUsn,
    int maxEntry = 100,
  }) {
    return _requestList(
      server: server,
      path: '/api2/tag/getSyncTags',
      token: token,
      query: {'afterUsn': '$afterUsn', 'maxEntry': '$maxEntry'},
    );
  }

  Future<List<SharedNote>> sharedNotes({
    required Uri server,
    required String token,
  }) async {
    final capabilities = await _requestJson(
      server: server,
      path: '/api2/shared/capabilities',
      method: 'GET',
      token: token,
    );
    if (capabilities['Ok'] != true ||
        capabilities['ProtocolVersion'] != 1 ||
        capabilities['Snapshot'] != true) {
      throw const ApiException('sharedProtocolUnsupported');
    }
    final snapshot = await _requestJson(
      server: server,
      path: '/api2/shared/snapshots',
      method: 'POST',
      token: token,
      body: {},
    );
    final id = snapshot['SnapshotId'];
    final total = snapshot['Total'];
    if (snapshot['Ok'] != true ||
        id is! String ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id) ||
        total is! int ||
        total < 0 ||
        total > 10000) {
      throw const ApiException('invalidSharedSnapshot');
    }
    final result = <SharedNote>[];
    final ids = <String>{};
    var received = 0;
    var cursor = '';
    while (true) {
      final page = await _requestJson(
        server: server,
        path: '/api2/shared/snapshots/$id/items',
        method: 'GET',
        token: token,
        query: {'pageToken': cursor},
      );
      if (page['Ok'] != true ||
          page['Items'] is! List ||
          page['Total'] != total ||
          page['Complete'] is! bool ||
          page['NextPageToken'] is! String) {
        throw const ApiException('invalidSharedSnapshot');
      }
      final items = page['Items'] as List;
      received += items.length;
      if (received > total) throw const ApiException('invalidSharedSnapshot');
      for (final item in items) {
        final data = _map(item);
        if (data['Kind'] == 'note') {
          final note = SharedNote.fromJson(_map(data['Note']));
          if (!ids.add(note.note.noteId)) {
            throw const ApiException('duplicateSharedNote');
          }
          result.add(note);
        } else if (data['Kind'] != 'notebook' && data['Kind'] != 'file') {
          throw const ApiException('invalidSharedSnapshot');
        }
      }
      if (page['Complete'] == true) {
        if (received != total || page['NextPageToken'] != '') {
          throw const ApiException('invalidSharedSnapshot');
        }
        break;
      }
      if (items.isEmpty ||
          received >= total ||
          page['NextPageToken'] != '$received') {
        throw const ApiException('invalidSharedSnapshot');
      }
      cursor = page['NextPageToken'] as String;
    }
    result.sort((a, b) {
      final order = a.note.title.toLowerCase().compareTo(
        b.note.title.toLowerCase(),
      );
      return order == 0 ? a.note.noteId.compareTo(b.note.noteId) : order;
    });
    return result;
  }

  Future<Note> sharedContent({
    required Uri server,
    required String token,
    required SharedNote shared,
  }) async {
    final data = await _requestJson(
      server: server,
      path: '/api2/shared/notes/${shared.note.noteId}/content',
      method: 'GET',
      token: token,
    );
    if (data['Ok'] != true ||
        data['NoteId'] != shared.note.noteId ||
        data['Content'] is! String) {
      throw const ApiException('invalidResponse');
    }
    if (data['Version'] != shared.version || data['Digest'] != shared.version) {
      throw const ApiException('sharedContentChanged');
    }
    return shared.note.copyWith(content: data['Content'] as String);
  }

  Future<void> logout({required Uri server, required String token}) async {
    await _requestJson(
      server: server,
      path: '/api2/auth/logout',
      method: 'POST',
      token: token,
      body: const <String, Object?>{},
    );
  }

  Future<Account> userInfo({required Uri server, required String token}) async {
    final data = await _requestJson(
      server: server,
      path: '/api2/user/info',
      method: 'GET',
      token: token,
    );
    return Account.fromJson(data, server: server);
  }

  Future<void> requestPasswordReset({
    required Uri server,
    required String email,
  }) async {
    final response = await _requestJson(
      server: server,
      path: '/api2/auth/password/request',
      method: 'POST',
      body: {'email': email},
    );
    if (response['Ok'] != true) throw const ApiException('invalidResponse');
  }

  Future<List<NoteHistory>> getHistories({
    required Uri server,
    required String token,
    required String noteId,
  }) async {
    final response = await _requestJson(
      server: server,
      path: '/api2/note/getHistories',
      method: 'GET',
      token: token,
      query: {'noteId': noteId},
    );
    if (response['Ok'] != true || response['Item'] is! List) {
      throw const ApiException('invalidResponse');
    }
    return (response['Item'] as List)
        .map((item) => NoteHistory.fromJson(_map(item)))
        .toList(growable: false);
  }

  Future<String> getHistoryContent({
    required Uri server,
    required String token,
    required String noteId,
    required String historyId,
  }) async {
    if (historyId.isEmpty) throw const ApiException('invalidHistoryId');
    final response = await _requestJson(
      server: server,
      path: '/api2/note/getHistoryContent',
      method: 'GET',
      token: token,
      query: {'noteId': noteId, 'historyId': historyId},
    );
    final item = _map(response['Item']);
    if (response['Ok'] != true ||
        item['HistoryId'] != historyId ||
        item['Content'] is! String) {
      throw const ApiException('invalidResponse');
    }
    return item['Content'] as String;
  }

  Future<Note> addNote({
    required Uri server,
    required String token,
    required Note note,
  }) async {
    final data = await _requestFormJson(
      server: server,
      path: '/api2/client/note/add',
      token: token,
      fields: _noteFields(note, isNew: true),
    );
    return Note.fromJson(data);
  }

  Future<Notebook> saveNotebook({
    required Uri server,
    required String token,
    required String title,
    String? parentNotebookId,
    Notebook? existing,
  }) async {
    final data = await _requestFormJson(
      server: server,
      path: existing == null
          ? '/api2/client/notebook/add'
          : '/api2/client/notebook/update',
      token: token,
      fields: {
        'title': title,
        'parentNotebookId':
            parentNotebookId ?? existing?.parentNotebookId ?? '',
        'seq': '${existing?.sequence ?? 0}',
        if (existing != null) 'notebookId': existing.notebookId,
        if (existing != null) 'usn': '${existing.usn}',
      },
    );
    final notebook = Notebook.fromJson(data);
    if (!RegExp(r'^[0-9a-fA-F]{24}$').hasMatch(notebook.notebookId) ||
        notebook.usn <= 0 ||
        (existing != null && notebook.notebookId != existing.notebookId)) {
      throw const ApiException('invalidResponse');
    }
    return notebook;
  }

  Future<void> deleteTrash({
    required Uri server,
    required String token,
    required Note note,
  }) async {
    // A new note may have reached the server before an add response was lost.
    // Never delete an unacknowledged server version using a guessed USN.
    if (note.usn == 0) {
      try {
        final current = await _requestJson(
          server: server,
          path: '/api2/note/getNote',
          method: 'GET',
          token: token,
          query: {'noteId': note.noteId},
        );
        if (current['NoteId'] == note.noteId && current['IsDeleted'] == true) {
          return;
        }
      } on ApiException catch (error) {
        if (error.code == 'notExists' && error.statusCode == null) return;
        rethrow;
      }
      throw const ApiException('unconfirmedNoteDeletion');
    }
    try {
      final response = await _requestFormJson(
        server: server,
        path: '/api2/client/note/deleteTrash',
        token: token,
        fields: {'noteId': note.noteId, 'usn': '${note.usn}'},
      );
      final usn = response['Usn'];
      if (response['Ok'] != true || usn is! int || usn <= note.usn) {
        throw const ApiException('invalidResponse');
      }
    } on ApiException catch (error) {
      // The previous attempt may have succeeded before its response was lost.
      if (error.code == 'notExists' && error.statusCode == null) return;
      rethrow;
    }
  }

  /// Bracket the body read with metadata reads: these API2 endpoints are
  /// separate requests and must not combine different remote revisions.
  Future<({Note note, bool filesConfirmedEmpty})> getConflictSnapshot({
    required Uri server,
    required String token,
    required String noteId,
  }) async {
    Future<Map<String, Object?>> metadata() async {
      final data = await _requestJson(
        server: server,
        path: '/api2/note/getNote',
        method: 'GET',
        token: token,
        query: {'noteId': noteId},
      );
      if (data['NoteId'] != noteId ||
          data['Usn'] is! int ||
          (data['Usn'] as int) <= 0 ||
          [
            'UserId',
            'NotebookId',
            'Title',
            'CreatedTime',
            'UpdatedTime',
          ].any((key) => data[key] is! String) ||
          [
            'IsMarkdown',
            'IsStar',
            'IsTrash',
            'IsDeleted',
          ].any((key) => data[key] is! bool) ||
          !data.containsKey('Tags') ||
          (data['Tags'] != null &&
              (data['Tags'] is! List ||
                  (data['Tags'] as List).any((tag) => tag is! String)))) {
        throw const ApiException('invalidResponse');
      }
      if (data['IsDeleted'] == true) throw const ApiException('conflict');
      return data;
    }

    final before = await metadata();
    final body = await _requestJson(
      server: server,
      path: '/api2/note/getNoteContent',
      method: 'GET',
      token: token,
      query: {'noteId': noteId},
    );
    if (body['NoteId'] != noteId ||
        body['Content'] is! String ||
        body['UserId'] != before['UserId']) {
      throw const ApiException('invalidResponse');
    }
    final after = await metadata();
    if (before['Usn'] != after['Usn']) {
      throw const ApiException('conflict');
    }
    return (
      note: Note.fromJson({...after, 'Content': body['Content']}),
      filesConfirmedEmpty:
          before['Files'] is List &&
          (before['Files'] as List).isEmpty &&
          after['Files'] is List &&
          (after['Files'] as List).isEmpty,
    );
  }

  Future<Note> updateNote({
    required Uri server,
    required String token,
    required Note note,
  }) async {
    // The server treats Files as the complete retained attachment list.
    // Until mobile attachment editing is implemented, preserve the current
    // remote references, guarded by the same USN used for the update.
    final current = await _requestJson(
      server: server,
      path: '/api2/note/getNote',
      method: 'GET',
      token: token,
      query: {'noteId': note.noteId},
    );
    if (current['NoteId'] != note.noteId || current['Usn'] is! num) {
      throw const ApiException('invalidResponse');
    }
    if (current['Usn'] != note.usn) throw const ApiException('conflict');
    if (!current.containsKey('Files') ||
        (current['Files'] != null && current['Files'] is! List)) {
      throw const ApiException('invalidResponse');
    }
    final fields = _noteFields(note, isNew: false);
    final files = current['Files'] as List? ?? const [];
    for (var index = 0; index < files.length; index++) {
      final file = _map(files[index]);
      final id = _string(file, 'FileId');
      if (!RegExp(r'^[0-9a-fA-F]{24}$').hasMatch(id) ||
          file['IsAttach'] is! bool) {
        throw const ApiException('invalidResponse');
      }
      fields.addAll({
        'Files[$index][FileId]': id,
        'Files[$index][LocalFileId]': id,
        'Files[$index][IsAttach]': '${file['IsAttach']}',
        'Files[$index][HasBody]': 'false',
        'Files[$index][Type]': file['Type']?.toString() ?? '',
        'Files[$index][Title]': file['Title']?.toString() ?? '',
      });
    }
    final data = await _requestFormJson(
      server: server,
      path: '/api2/client/note/update',
      token: token,
      fields: fields,
    );
    return Note.fromJson(data);
  }

  Future<Map<String, Object?>> _requestFormJson({
    required Uri server,
    required String path,
    required String token,
    required Map<String, String> fields,
  }) async {
    final uri = _uri(server, path, token: token);
    late http.Response response;
    try {
      response = await _http
          .post(uri, body: fields)
          .timeout(const Duration(minutes: 2));
    } on Exception {
      throw const ApiException('networkUnavailable');
    }
    return _decodeMapResponse(response);
  }

  Future<List<Map<String, Object?>>> _requestList({
    required Uri server,
    required String path,
    required String token,
    Map<String, String> query = const {},
  }) async {
    final value = await _request(
      server: server,
      path: path,
      method: 'GET',
      token: token,
      query: query,
    );
    if (value is! List) throw const ApiException('invalidResponse');
    return value.map((item) => _map(item)).toList(growable: false);
  }

  Future<Map<String, Object?>> _requestJson({
    required Uri server,
    required String path,
    required String method,
    String? token,
    Map<String, String> query = const {},
    Object? body,
  }) async {
    final value = await _request(
      server: server,
      path: path,
      method: method,
      token: token,
      query: query,
      body: body,
    );
    return _map(value);
  }

  Future<Object?> _request({
    required Uri server,
    required String path,
    required String method,
    String? token,
    Map<String, String> query = const {},
    Object? body,
  }) async {
    final uri = _uri(server, path, token: token, query: query);
    late http.Response response;
    try {
      response = method == 'POST'
          ? await _http
                .post(
                  uri,
                  headers: const {'Content-Type': 'application/json'},
                  body: jsonEncode(body),
                )
                .timeout(const Duration(seconds: 60))
          : await _http.get(uri).timeout(const Duration(seconds: 60));
    } on Exception {
      throw const ApiException('networkUnavailable');
    }
    return _decodeResponse(response);
  }

  Uri _uri(
    Uri server,
    String path, {
    String? token,
    Map<String, String> query = const {},
  }) => server
      .resolve(path)
      .replace(
        queryParameters: <String, String>{
          ...query,
          'token': ?token,
          'v': 'mobile_$clientVersion',
        },
      );

  static Object? _decodeResponse(http.Response response) {
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw ApiException('invalidJSON', statusCode: response.statusCode);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final data = decoded is Map ? _map(decoded) : const <String, Object?>{};
      throw ApiException(
        data['Msg']?.toString() ?? 'http${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    if (decoded is Map) {
      final data = _map(decoded);
      if (data['Ok'] == false) {
        throw ApiException(data['Msg']?.toString() ?? 'requestFailed');
      }
    }
    return decoded;
  }

  static Map<String, Object?> _decodeMapResponse(http.Response response) =>
      _map(_decodeResponse(response));

  static Map<String, String> _noteFields(Note note, {required bool isNew}) {
    final fields = <String, String>{
      if (isNew) 'ClientNoteId': note.noteId else 'NoteId': note.noteId,
      'NotebookId': note.notebookId,
      'Title': note.title,
      'Content': note.content,
      'IsMarkdown': '${note.isMarkdown}',
      'IsTrash': '${note.isTrash}',
      'IsBlog': 'false',
      'IsStar': '${note.isStarred}',
      'CreatedTime': note.createdTime,
      'UpdatedTime': note.updatedTime,
    };
    if (!isNew) fields['Usn'] = '${note.usn}';
    for (var index = 0; index < note.tags.length; index++) {
      fields['Tags[$index]'] = note.tags[index];
    }
    return fields;
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is! Map) throw const ApiException('invalidResponse');
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  static String _string(Map<String, Object?> value, String key) {
    final result = value[key]?.toString() ?? '';
    if (result.isEmpty) throw const ApiException('invalidResponse');
    return result;
  }
}
