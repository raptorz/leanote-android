import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gemsnote/domain/models/note_image_reference.dart';
import 'package:gemsnote/ui/markdown_note_body.dart';

void main() {
  final server = Uri.parse('https://example.test');
  const id = '507f1f77bcf86cd799439011';
  test('only same-origin known stored image references yield IDs', () {
    for (final path in [
      '/api2/file/getImage',
      '/api/file/getImage',
      '/file/outputImage',
    ]) {
      expect(cachedImageFileId(Uri.parse('$path?fileId=$id'), server), id);
      expect(
        cachedImageFileId(
          Uri.parse('https://example.test$path?fileId=$id'),
          server,
        ),
        id,
      );
    }
    for (final value in [
      'https://evil.test/api2/file/getImage?fileId=$id',
      'http://example.test/api2/file/getImage?fileId=$id',
      'https://user:pwd@example.test/api2/file/getImage?fileId=$id',
      '/api2/file/getAttach?fileId=$id',
      'file:///private/image.png',
      'data:image/png;base64,AAAA',
      '/api2/file/getImage?fileId=$id&fileId=$id',
      '/api2/file/getImage?fileId=$id#anchor',
      '/api2/file/getImage?fileId=invalid',
      '/private/$id',
      'http:broken',
    ]) {
      expect(
        cachedImageFileId(Uri.parse(value), server),
        isNull,
        reason: value,
      );
    }
  });
  testWidgets(
    'Markdown uses supplied cache loader, without remote image providers',
    (tester) async {
      final requests = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownNoteBody(
              content: '![photo](/api2/file/getImage?fileId=$id)',
              loadCachedImage: (uri) async {
                requests.add(uri);
                return File('assets/images/gemsnote_s.png').readAsBytesSync();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(requests.single.queryParameters['fileId'], id);
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as ResizeImage).imageProvider, isA<MemoryImage>());
      expect(image.semanticLabel, 'photo');
    },
  );
  for (final failure in ['missing', 'error', 'corrupt']) {
    testWidgets('cache $failure leaves readable placeholder', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownNoteBody(
              content: '![photo](/api2/file/getImage?fileId=$id)',
              loadCachedImage: (_) async {
                if (failure == 'error') throw StateError('unavailable');
                return failure == 'corrupt' ? Uint8List.fromList([0]) : null;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('图片尚未缓存或无法读取：photo'), findsOneWidget);
    });
  }
}
