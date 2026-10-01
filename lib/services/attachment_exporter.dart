import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'note_exporter.dart';

class AttachmentExporter {
  AttachmentExporter({SaveNoteFile? save}) : _save = save ?? _saveSystem;
  final SaveNoteFile _save;

  static Future<Uri?> _saveSystem({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) => FilePicker.saveFile(
    fileName: fileName,
    bytes: bytes,
    mimeType: mimeType,
    dialogTitle: '保存附件',
  );

  Future<bool> save(String title, Uint8List bytes) async {
    if (bytes.length > 32 * 1024 * 1024) throw StateError('附件超过 32 MiB');
    return await _save(
          fileName: NoteExporter.safeFileName(title, '', fallback: '附件'),
          bytes: bytes,
          mimeType: 'application/octet-stream',
        ) !=
        null;
  }
}
