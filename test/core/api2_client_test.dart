import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gemsnote/core/api/api2_client.dart';
import 'package:gemsnote/core/api/api_exception.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('login uses the finalized API2 JSON contract', () async {
    final client = Api2Client(
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api2/auth/login');
        expect(request.url.queryParameters['v'], 'mobile_1.0.0');
        expect(jsonDecode(request.body), {'email': 'admin', 'pwd': 'secret'});
        return http.Response(
          jsonEncode({
            'Ok': true,
            'Token': 'token-1',
            'User': {
              'UserId': '507f1f77bcf86cd799439011',
              'Username': 'admin',
              'Email': 'admin@example.test',
              'Logo': '',
            },
            'Server': {
              'Name': 'gemsnote',
              'Version': '1.0.0',
              'MinVersion': '',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await client.login(
      server: Uri.parse('https://notes.example.test/'),
      identity: 'admin',
      password: 'secret',
    );

    expect(result.token, 'token-1');
    expect(result.account.username, 'admin');
    expect(result.serverVersion, '1.0.0');
  });

  test('login rejects a non-Gemsnote server response', () async {
    final client = Api2Client(
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'Ok': true,
            'Token': 'token-1',
            'User': {'UserId': 'user-1'},
            'Server': {'Name': 'leanote', 'Version': '1.0.0'},
          }),
          200,
        ),
      ),
    );

    expect(
      () => client.login(
        server: Uri.parse('https://notes.example.test/'),
        identity: 'admin',
        password: 'secret',
      ),
      throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'code',
          'serverMigrationRequired',
        ),
      ),
    );
  });
}
