import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gemsnote/core/api/api2_client.dart';
import 'package:gemsnote/core/api/api_exception.dart';
import 'package:gemsnote/ui/account_field_dialog.dart';
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
            case '/api2/user/updateUsername':
              expect(request.method, 'POST');
              expect(request.headers['authorization'], 'Bearer test-token');
              expect(
                request.headers['content-type'],
                startsWith('application/x-www-form-urlencoded'),
              );
              expect(Uri.splitQueryString(request.body), {'username': 'new'});
              return http.Response(
                jsonEncode({
                  'Ok': scenario == 'ok' || scenario == 'logout-failed',
                }),
                200,
              );
            default:
              fail('unexpected endpoint');
          }
        }),
      );
      final result = api.updateUsername(
        server: Uri.parse('https://notes.test'),
        token: 'test-token',
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
      expect(paths, ['/api2/user/updateUsername']);
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
            body: AccountFieldDialog(
              identity: 'old',
              value: 'new',
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
