import 'package:flutter/material.dart';

import '../sync/sync_coordinator.dart';

/// Keeps the operation on one modal route and returns errors to its caller.
Future<void> showSyncProgress(
  BuildContext context, {
  required Future<void> Function(SyncProgressCallback progress) synchronize,
}) async {
  final result = await showDialog<_SyncResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SyncProgressDialog(synchronize: synchronize),
  );
  if (result?.error case final Object error) {
    Error.throwWithStackTrace(error, result!.stackTrace!);
  }
}

class _SyncResult {
  const _SyncResult([this.error, this.stackTrace]);

  final Object? error;
  final StackTrace? stackTrace;
}

class _SyncProgressDialog extends StatefulWidget {
  const _SyncProgressDialog({required this.synchronize});

  final Future<void> Function(SyncProgressCallback progress) synchronize;

  @override
  State<_SyncProgressDialog> createState() => _SyncProgressDialogState();
}

class _SyncProgressDialogState extends State<_SyncProgressDialog> {
  SyncProgress? _progress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (!mounted) return;
    var result = const _SyncResult();
    try {
      await widget.synchronize((value) {
        if (mounted) setState(() => _progress = value);
      });
    } on Object catch (error, stack) {
      result = _SyncResult(error, stack);
    }
    if (mounted) Navigator.of(context).pop(result);
  }

  String get _label {
    final progress = _progress;
    if (progress == null) return '正在准备同步…';
    final count = progress.completed;
    return switch (progress.stage) {
      SyncStage.uploading => '正在上传本地修改，已上传 $count 篇',
      SyncStage.notebooks => '正在下载笔记本，已接收 $count 个',
      SyncStage.notes => '正在下载笔记正文，已接收 $count 篇',
      SyncStage.tags => '正在下载标签，已接收 $count 个',
      SyncStage.saving => '正在保存本地数据…',
    };
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: AlertDialog(
      title: const Text('正在同步'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LinearProgressIndicator(),
          const SizedBox(height: 16),
          Semantics(liveRegion: true, child: Text(_label)),
          const SizedBox(height: 8),
          const Text('请保持应用打开，完成后此窗口会自动关闭。'),
        ],
      ),
    ),
  );
}
