import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gemsnote/core/api/api2_client.dart';
import 'package:gemsnote/core/api/api_exception.dart';
import 'package:gemsnote/domain/models/attachment_upload.dart';
import 'package:gemsnote/services/attachment_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'note_import_test.dart' show PickedSource;

void main() {
  test(
    'attachment picker cancellation, basename and size validation',
    () async {
      expect(await AttachmentPicker(pick: () async => null).pick(), isNull);
      final picked = await AttachmentPicker(
        pick: () async =>
            PickedSource('dir/example.txt', Uint8List.fromList([1, 2])),
      ).pick();
      expect(picked!.name, 'example.txt');
      expect(picked.bytes, [1, 2]);
      final oversized = PickedSource(
        'big.bin',
        Uint8List(1),
        reportedSize: AttachmentUpload.maxBytes + 1,
      );
      await expectLater(
        AttachmentPicker(pick: () async => oversized).pick(),
        throwsFormatException,
      );
      expect(oversized.read, false);
      expect(
        () => AttachmentUpload(name: 'a', bytes: Uint8List(0)),
        throwsFormatException,
      );
      expect(
        () => AttachmentUpload(name: '../a', bytes: Uint8List(1)),
        throwsFormatException,
      );
      expect(
        () => AttachmentUpload(name: 'a\r\nb', bytes: Uint8List(1)),
        throwsFormatException,
      );
    },
  );
  for (final scenario in [
    'ok',
    'foreign-note',
    'wrong-session',
    'rejected',
    'unknown-result',
  ]) {
    test('API2 attachment upload contract: $scenario', () async {
      const noteId = '507f1f77bcf86cd799439011';
      const fileId = '507f1f77bcf86cd799439012';
      var uploads = 0;
      final paths = <String>[];
      final api = Api2Client(
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          switch (request.url.path) {
            case '/api2/note/getNote':
              expect(request.url.queryParameters['token'], 't');
              return http.Response(
                jsonEncode({
                  'NoteId': noteId,
                  'UserId': scenario == 'foreign-note' ? 'other' : 'u',
                }),
                200,
              );
            case '/api2/auth/session':
              expect(request.followRedirects, false);
              return http.Response(
                '{"Ok":true}',
                200,
                headers: {'set-cookie': 'session=s; Path=/; HttpOnly'},
              );
            case '/api2/bootstrap':
              return http.Response(
                jsonEncode({
                  'Ok': true,
                  'User': {
                    'UserId': scenario == 'wrong-session' ? 'other' : 'u',
                  },
                }),
                200,
              );
            case '/api2/attachments/upload':
              uploads++;
              expect(request.method, 'POST');
              expect(request.followRedirects, false);
              expect(request.headers['Cookie'], 'session=s');
              expect(
                request.headers['content-type'],
                startsWith('multipart/form-data'),
              );
              expect(request.body, contains('name="noteId"'));
              expect(request.body, contains(noteId));
              expect(
                request.body,
                contains('name="file"; filename="example.txt"'),
              );
              expect(request.body, contains('payload'));
              return http.Response(
                jsonEncode({
                  'Ok': scenario != 'rejected',
                  'Id': scenario == 'unknown-result' ? '' : fileId,
                  'Msg': 'denied',
                }),
                200,
              );
            case '/api2/logout':
              return http.Response('{"Ok":true}', 200);
          }
          throw StateError('Unexpected request ${request.url.path}');
        }),
      );
      final future = api.uploadAttachment(
        server: Uri.parse('https://example.com'),
        token: 't',
        userId: 'u',
        identity: 'admin',
        password: 'pass',
        noteId: noteId,
        file: AttachmentUpload(
          name: 'example.txt',
          bytes: Uint8List.fromList(utf8.encode('payload')),
        ),
      );
      if (scenario == 'ok') {
        expect(await future, fileId);
      } else {
        await expectLater(future, throwsA(isA<ApiException>()));
      }
      expect(
        uploads,
        ['foreign-note', 'wrong-session'].contains(scenario) ? 0 : 1,
      );
      if (scenario != 'foreign-note') expect(paths.last, '/api2/logout');
    });
  }
}
