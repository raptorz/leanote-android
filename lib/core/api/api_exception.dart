class ApiException implements Exception {
  const ApiException(this.code, {this.statusCode});

  final String code;
  final int? statusCode;

  @override
  String toString() =>
      code == 'sharedContentChanged' ? '共享笔记已更新，请刷新列表后重试' : code;
}
