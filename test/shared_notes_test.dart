import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gemsnote/core/api/api2_client.dart';
import 'package:gemsnote/core/api/api_exception.dart';
import 'package:gemsnote/domain/models/shared_note.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final server = Uri.parse('https://example.test/');
  const id = '507f1f77bcf86cd799439011';
  final version = List.filled(64, 'a').join();
  final data = <String, Object?>{
    'NoteId': id,
    'OwnerUserId': '507f1f77bcf86cd799439012',
    'Title': 'shared',
    'Version': version,
    'IsMarkdown': true,
  };
  for (final mode in [
    'success',
    'expired',
    'stalled',
    'wrongTotal',
    'duplicate',
    'empty',
  ]) {
    test('shared snapshot $mode', () async {
      var pages = 0;
      final api = Api2Client(
        httpClient: MockClient((request) async {
          expect(request.url.queryParameters['token'], 'test');
          Object response;
          if (request.url.path.endsWith('/capabilities')) {
            response = {'Ok': true, 'ProtocolVersion': 1, 'Snapshot': true};
          } else if (request.url.path.endsWith('/snapshots')) {
            expect(request.method, 'POST');
            expect(jsonDecode(request.body), {});
            response = {
              'Ok': true,
              'SnapshotId': 'snapshot-1',
              'Total': mode == 'empty' ? 0 : 2,
            };
          } else {
            expect(request.url.path, '/api2/shared/snapshots/snapshot-1/items');
            pages++;
            expect(
              request.url.queryParameters['pageToken'],
              pages == 1 ? '' : '1',
            );
            if (mode == 'expired') {
              return http.Response('{"Ok":false,"Msg":"snapshotExpired"}', 200);
            }
            response = {
              'Ok': true,
              'Total': mode == 'wrongTotal'
                  ? 3
                  : mode == 'empty'
                  ? 0
                  : 2,
              'Items': mode == 'empty' || mode == 'stalled'
                  ? []
                  : [
                      if (pages == 1 || mode == 'duplicate')
                        {'Kind': 'note', 'Note': data}
                      else
                        {'Kind': 'file', 'File': {}},
                    ],
              'Complete': mode == 'empty' || pages == 2,
              'NextPageToken': mode == 'empty' || pages == 2 ? '' : '1',
            };
          }
          return http.Response(jsonEncode(response), 200);
        }),
      );
      final operation = api.sharedNotes(server: server, token: 'test');
      if (mode == 'success' || mode == 'empty') {
        final notes = await operation;
        expect(notes.length, mode == 'empty' ? 0 : 1);
        if (notes.isNotEmpty) {
          expect(notes.single.note.userId, data['OwnerUserId']);
        }
      } else {
        await expectLater(operation, throwsA(isA<ApiException>()));
      }
      expect(pages, lessThanOrEqualTo(2));
    });
  }
  for (final mode in ['success', 'changed', 'denied', 'wrongId']) {
    test('shared body $mode', () async {
      final api = Api2Client(
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api2/shared/notes/$id/content');
          if (mode == 'denied') {
            return http.Response('{"Ok":false,"Msg":"noPermission"}', 200);
          }
          return http.Response(
            jsonEncode({
              'Ok': true,
              'NoteId': mode == 'wrongId' ? 'wrong' : id,
              'Version': mode == 'changed' ? 'new' : version,
              'Digest': version,
              'Content': '',
            }),
            200,
          );
        }),
      );
      final operation = api.sharedContent(
        server: server,
        token: 'test',
        shared: SharedNote.fromJson(data),
      );
      if (mode == 'success') {
        expect((await operation).content, '');
      } else {
        await expectLater(operation, throwsA(isA<ApiException>()));
      }
    });
  }
}
