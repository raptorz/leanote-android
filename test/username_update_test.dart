import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gemsnote/core/api/api2_client.dart';
import 'package:gemsnote/core/api/api_exception.dart';
import 'package:gemsnote/ui/username_dialog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final scenario in [
    'ok',
    'wrong-user',
    'wrong-password',
    'redirect',
    'rejected',
    'logout-failed',
  ]) {
    test('username session identity and cleanup: $scenario', () async {
      final paths = <String>[];
      final api = Api2Client(
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          expect(request.url.host, 'notes.test');
          expect(request.url.queryParameters.containsKey('token'), false);
          expect(request.followRedirects, false);
          switch (request.url.path) {
            case '/api2/auth/session':
              expect(request.headers.containsKey('cookie'), false);
              expect(jsonDecode(request.body), {
                'email': 'old',
                'pwd': 'secret',
              });
              if (scenario == 'wrong-password') {
                return http.Response('{"Ok":false}', 200);
              }
              if (scenario == 'redirect') {
                return http.Response(
                  '',
                  302,
                  headers: {'location': 'https://evil.test/'},
                );
              }
              return http.Response(
                '{"Ok":true}',
                200,
                headers: {
                  'set-cookie': 'session=abc; Path=/; HttpOnly; Expires=Wed, 01 Jan 2031 00:00:00 GMT, locale=zh; Path=/',
                },
              );
            case '/api2/bootstrap':
              expect(request.headers['cookie'], contains('session=abc'));
              return http.Response(
                jsonEncode({
                  'Ok': true,
                  'User': {'UserId': scenario == 'wrong-user' ? 'other' : 'u'},
                }),
                200,
              );
            case '/api2/user/updateUsername':
              expect(request.method, 'POST');
              expect(
                request.headers['content-type'],
                startsWith('application/x-www-form-urlencoded'),
              );
              expect(Uri.splitQueryString(request.body), {'username': 'new'});
              return http.Response(
                jsonEncode({'Ok': scenario != 'rejected'}),
                200,
              );
            case '/api2/logout':
              return http.Response(
                '{"Ok":true}',
                scenario == 'logout-failed' ? 503 : 200,
              );
            default:
              fail('unexpected endpoint');
          }
        }),
      );
      final result = api.updateUsername(
        server: Uri.parse('https://notes.test'),
        userId: 'u',
        identity: 'old',
        password: 'secret',
        username: 'new',
      );
      if (scenario == 'ok' || scenario == 'logout-failed') {
        await result;
      } else {
        await expectLater(result, throwsA(isA<ApiException>()));
      }
      if (scenario == 'wrong-user') {
        expect(paths, isNot(contains('/api2/user/updateUsername')));
      }
      if (scenario != 'wrong-password' && scenario != 'redirect') {
        expect(paths.last, '/api2/logout');
      }
      expect(
        paths.where((p) => p == '/api2/user/updateUsername').length,
        lessThanOrEqualTo(1),
      );
    });
  }
  testWidgets(
    'dialog validates required input, clears password on failure and permits retry',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UsernameDialog(
              identity: 'old',
              username: 'new',
              save: (identity, password, username) async {
                calls++;
                expect(password, 'secret');
                throw StateError('failed');
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(calls, 0);
      expect(find.text('请填写全部字段'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(1), 'secret');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
        '',
      );
      expect(find.textContaining('修改失败'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
    },
  );
}
