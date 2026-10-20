import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Test setup only: provision users through the administrator API2 endpoint.
/// All requests still pass through the caller's loopback/API2-only client.
class FixtureSession {
  FixtureSession(this.client, this.server);
  final http.Client client;
  final Uri server;
  final _cookies = <String, String>{};

  Future<void> login(String identity, String password) async {
    final result = await request('/api2/auth/session', {
      'email': identity,
      'pwd': password,
    }, json: true);
    expect(result['Ok'], isTrue);
    expect(_cookies, isNotEmpty);
  }

  Future<Map<String, dynamic>> request(
    String path,
    Map<String, String> fields, {
    bool json = false,
  }) async => await _request(path, fields, json: json) as Map<String, dynamic>;

  Future<void> revokeNote(String noteId, String recipientId) async {
    expect(
      await _request('/api2/share/deleteShareNote', {
        'noteId': noteId,
        'toUserId': recipientId,
      }),
      isTrue,
    );
  }

  Future<Object?> _request(
    String path,
    Map<String, String> fields, {
    bool json = false,
  }) async {
    final request = http.Request('POST', server.resolve(path))
      ..followRedirects = false
      ..headers['X-Requested-With'] = 'XMLHttpRequest';
    if (_cookies.isNotEmpty) {
      request.headers['Cookie'] = _cookies.entries
          .map((e) => '${e.key}=${e.value}')
          .join('; ');
    }
    if (json) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(fields);
    } else {
      request.bodyFields = fields;
    }
    final response = await http.Response.fromStream(await client.send(request))
        .timeout(const Duration(seconds: 30));
    final header = response.headers['set-cookie'];
    if (header != null) {
      for (final part in header.split(RegExp(r',(?=\s*[^\s;,=]+=)'))) {
        final cookie = Cookie.fromSetCookieValue(part.trim());
        _cookies[cookie.name] = cookie.value;
      }
    }
    expect(response.statusCode, 200);
    return jsonDecode(response.body);
  }

  Future<void> close() async {
    await _request('/api2/logout', {});
    _cookies.clear();
  }
}
