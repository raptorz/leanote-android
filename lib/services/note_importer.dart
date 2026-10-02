import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class ImportedNote {
  const ImportedNote(this.title, this.content, this.isMarkdown);
  final String title;
  final String content;
  final bool isMarkdown;
}

class NoteImporter {
  NoteImporter({Future<PlatformFile?> Function()? pick})
    : _pick = pick ?? _pickSystem;
  final Future<PlatformFile?> Function() _pick;
  static const maxBytes = 32 * 1024 * 1024;
  static Future<PlatformFile?> _pickSystem() => FilePicker.pickFile(
    dialogTitle: '导入笔记原文',
    type: FileType.custom,
    allowedExtensions: ['md', 'markdown', 'txt', 'html', 'htm'],
  );

  Future<ImportedNote?> pick() async {
    final file = await _pick();
    if (file == null) return null;
    final name = file.name.replaceAll('\\', '/').split('/').last;
    final dot = name.lastIndexOf('.');
    final extension = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    if (!['md', 'markdown', 'txt', 'html', 'htm'].contains(extension)) {
      throw const FormatException('仅支持 Markdown、TXT 或 HTML 文件');
    }
    if ((file.lengthSync() ?? 0) > maxBytes) throw StateError('文件超过 32 MiB');
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.readAsByteStream().timeout(
      const Duration(seconds: 30),
    )) {
      if (bytes.length + chunk.length > maxBytes) {
        throw StateError('文件超过 32 MiB');
      }
      bytes.add(chunk);
    }
    var content = utf8.decode(bytes.takeBytes());
    if (content.startsWith('\ufeff')) content = content.substring(1);
    if (content.contains('\u0000')) {
      throw const FormatException('不支持二进制内容，请选择 UTF-8 文本');
    }
    var title = name
        .substring(0, dot)
        .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '')
        .trim();
    title = String.fromCharCodes(title.runes.take(200));
    if (title.isEmpty) title = '导入的笔记';
    return ImportedNote(
      title,
      content,
      extension != 'html' && extension != 'htm',
    );
  }
}
