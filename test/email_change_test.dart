import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gemsnote/core/api/api2_client.dart';
import 'package:gemsnote/core/api/api_exception.dart';
import 'package:gemsnote/ui/account_field_dialog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final scenario in ['sent', 'wrong-user', 'mail-failed']) {
    test(
      'email change verified session and form contract: $scenario',
      () async {
        final paths = <String>[];
        final api = Api2Client(
          httpClient: MockClient((request) async {
            paths.add(request.url.path);
            expect(request.followRedirects, false);
            expect(request.url.queryParameters, isEmpty);
            switch (request.url.path) {
              case '/api2/auth/session':
                expect(jsonDecode(request.body), {
                  'email': 'old@test.com',
                  'pwd': 'p&=secret',
                });
                return http.Response(
                  '{"Ok":true}',
                  200,
                  headers: {'set-cookie': 'session=private; Path=/'},
                );
              case '/api2/bootstrap':
                expect(request.headers['cookie'], 'session=private');
                return http.Response(
                  jsonEncode({
                    'Ok': true,
                    'User': {
                      'UserId': scenario == 'wrong-user' ? 'other' : 'u',
                    },
                  }),
                  200,
                );
              case '/api2/web/emailChange':
                expect(request.method, 'POST');
                expect(request.headers['cookie'], 'session=private');
                expect(
                  request.headers['content-type'],
                  startsWith('application/x-www-form-urlencoded'),
                );
                expect(Uri.splitQueryString(request.body), {
                  'email': 'new+notes@test.com',
                  'pwd': 'p&=secret',
                });
                return http.Response(
                  jsonEncode({'Ok': scenario == 'sent', 'Msg': 'smtpError'}),
                  200,
                );
              case '/api2/logout':
                return http.Response('{"Ok":true}', 200);
              default:
                fail('unexpected path');
            }
          }),
        );
        final result = api.requestEmailChange(
          server: Uri.parse('https://notes.test'),
          userId: 'u',
          identity: 'old@test.com',
          password: 'p&=secret',
          email: 'new+notes@test.com',
        );
        if (scenario == 'sent') {
          await result;
        } else {
          await expectLater(result, throwsA(isA<ApiException>()));
        }
        expect(paths.last, '/api2/logout');
        expect(
          paths.where((p) => p == '/api2/web/emailChange').length,
          scenario == 'wrong-user' ? 0 : 1,
        );
      },
    );
  }
  testWidgets(
    'email requires valid input, explains verification and submits once',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => AccountFieldDialog(
                    identity: 'old@test.com',
                    value: '',
                    emailChange: true,
                    save: (identity, password, value) async {
                      calls++;
                      expect(value, 'new+notes@test.com');
                      expect(password, 'secret');
                    },
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('邮箱才会变更'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(1), 'secret');
      await tester.enterText(find.byType(TextField).at(2), 'invalid');
      await tester.tap(find.text('发送验证邮件'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.text('请输入有效的邮箱地址'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField).at(2),
        'new+notes@test.com',
      );
      await tester.tap(find.text('发送验证邮件'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.byType(AccountFieldDialog), findsNothing);
    },
  );
}
