class ApiException implements Exception {
  const ApiException(this.code, {this.statusCode});

  final String code;
  final int? statusCode;

  @override
  String toString() => switch (code) {
    'sharedContentChanged' => '共享笔记已更新，请刷新列表后重试',
    'historyFileMissing' => '历史文件已丢失，无法完整恢复此版本',
    'historyFilesUnknown' => '此历史版本缺少完整附件清单，仅支持恢复正文',
    'historyRestoreFailed' => '恢复失败，请刷新笔记并检查历史记录后重试',
    _ => code,
  };
}
