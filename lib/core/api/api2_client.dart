import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/account.dart';
import '../../domain/models/note.dart';
import '../../domain/models/note_history.dart';
import '../../domain/models/notebook.dart';
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
    String parentNotebookId = '',
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
        'parentNotebookId': existing?.parentNotebookId ?? parentNotebookId,
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
