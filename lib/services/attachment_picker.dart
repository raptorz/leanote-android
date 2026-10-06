import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../domain/models/attachment_upload.dart';

class AttachmentPicker {
  AttachmentPicker({Future<PlatformFile?> Function()? pick})
    : _pick = pick ?? _system;
  final Future<PlatformFile?> Function() _pick;
  static Future<PlatformFile?> _system() =>
      FilePicker.pickFile(dialogTitle: '选择附件');

  Future<AttachmentUpload?> pick() async {
    final file = await _pick();
    if (file == null) return null;
    if ((file.lengthSync() ?? 0) > AttachmentUpload.maxBytes) {
      throw const FormatException('附件不能超过 32 MiB');
    }
    final name = file.name.replaceAll('\\', '/').split('/').last;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.readAsByteStream().timeout(
      const Duration(seconds: 30),
    )) {
      if (builder.length + chunk.length > AttachmentUpload.maxBytes) {
        throw const FormatException('附件不能超过 32 MiB');
      }
      builder.add(chunk);
    }
    return AttachmentUpload(name: name, bytes: builder.takeBytes());
  }
}
