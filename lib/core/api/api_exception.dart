class ApiException implements Exception {
  const ApiException(this.code, {this.statusCode});

  final String code;
  final int? statusCode;

  @override
  String toString() => switch (code) {
    'imageAlreadyReferenced' => '图片已被笔记或历史版本引用，不能清理',
    'uploadNotFound' => '未找到该图片的上传回执，请核实后重试',
    'uploadAlreadyCleaned' => '此上传已经清理，请用本地原件新建上传任务',
    'creationKeyDeleted' => '该笔记本已在服务端删除，请核实本地创建任务',
    'creationKeyUnavailable' => '笔记本创建键不可用，请核实本地创建任务',
    'sharedContentChanged' => '共享笔记已更新，请刷新列表后重试',
    'historyFileMissing' => '历史文件已丢失，无法完整恢复此版本',
    'historyFilesUnknown' => '此历史版本缺少完整附件清单，仅支持恢复正文',
    'historyRestoreFailed' => '恢复失败，请刷新笔记并检查历史记录后重试',
    _ => code,
  };
}
