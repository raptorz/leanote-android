import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'note_exporter.dart';

/// Saves already retrieved bytes, without requesting media or changing cache state.
class ImageExporter {
  ImageExporter({SaveNoteFile? save}) : _save = save ?? _saveSystem;
  final SaveNoteFile _save;

  static Future<Uri?> _saveSystem({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) => FilePicker.saveFile(
    fileName: fileName,
    bytes: bytes,
    mimeType: mimeType,
    dialogTitle: '保存图片',
  );

  Future<bool> save(String title, Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) {
      throw StateError('图片大小不支持');
    }
    bool starts(List<int> signature, [int offset = 0]) =>
        bytes.length >= offset + signature.length &&
        List.generate(
          signature.length,
          (i) => bytes[offset + i] == signature[i],
        ).every((match) => match);
    final String extension;
    final String mime;
    if (starts([137, 80, 78, 71, 13, 10, 26, 10])) {
      extension = '.png';
      mime = 'image/png';
    } else if (starts([255, 216, 255])) {
      extension = '.jpg';
      mime = 'image/jpeg';
    } else if (starts([71, 73, 70, 56, 55, 97]) ||
        starts([71, 73, 70, 56, 57, 97])) {
      extension = '.gif';
      mime = 'image/gif';
    } else if (starts([82, 73, 70, 70]) && starts([87, 69, 66, 80], 8)) {
      extension = '.webp';
      mime = 'image/webp';
    } else {
      throw StateError('不支持的图片格式');
    }
    // Use actual bytes, not server metadata, to select the output format.
    final name = title.replaceFirst(
      RegExp(r'\.(png|jpe?g|gif|webp)$', caseSensitive: false),
      '',
    );
    return await _save(
          fileName: NoteExporter.safeFileName(name, extension, fallback: '图片'),
          bytes: bytes,
          mimeType: mime,
        ) !=
        null;
  }
}
