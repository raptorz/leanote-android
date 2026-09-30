import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../domain/models/note.dart';

typedef SaveNoteFile = Future<Uri?> Function({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
});

class NoteExporter {
  NoteExporter({SaveNoteFile? save}) : _save = save ?? _saveSystem;
  final SaveNoteFile _save;

  static Future<Uri?> _saveSystem({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) => FilePicker.saveFile(
    fileName: fileName,
    bytes: bytes,
    mimeType: mimeType,
    dialogTitle: '导出笔记',
  );

  static String fileName(Note note) {
    final extension = note.isMarkdown ? '.md' : '.html';
    return safeFileName(note.title, extension, fallback: '未命名笔记');
  }

  static String safeFileName(
    String name,
    String extension, {
    required String fallback,
  }) {
    var title = name
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f\x7f]'), '_')
        .trim();
    title = title.replaceAll(RegExp(r'^\.+|[. ]+$'), '');
    if (title.toLowerCase().endsWith(extension)) {
      title = title.substring(0, title.length - extension.length);
    }
    // Bound UTF-8 bytes as well as characters: emoji can consume four bytes.
    final safeRunes = <int>[];
    var byteLength = 0;
    for (final rune in title.runes.take(80)) {
      final size = utf8.encode(String.fromCharCode(rune)).length;
      if (byteLength + size > 200) break;
      safeRunes.add(rune);
      byteLength += size;
    }
    title = String.fromCharCodes(safeRunes).trim();
    if (title.isEmpty) title = fallback;
    return '$title$extension';
  }

  /// Exports exactly the displayed source; never render/execute HTML or fetch media.
  Future<bool> export(Note note) async {
    final bytes = Uint8List.fromList(utf8.encode(note.content));
    if (bytes.length > 32 * 1024 * 1024) {
      throw StateError('笔记原文超过 32 MiB，暂不支持导出');
    }
    return await _save(
          fileName: fileName(note),
          bytes: bytes,
          mimeType: note.isMarkdown ? 'text/markdown' : 'text/html',
        ) !=
        null;
  }
}
