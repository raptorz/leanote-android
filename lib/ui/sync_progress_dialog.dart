import '../l10n/app_strings.dart';

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
    if (progress == null) return trNow(context, 'm0402');
    final count = progress.completed;
    return switch (progress.stage) {
      SyncStage.uploading => trNow(context, 'm0403', [count]),
      SyncStage.notebooks => trNow(context, 'm0404', [count]),
      SyncStage.notes => trNow(context, 'm0405', [count]),
      SyncStage.tags => trNow(context, 'm0406', [count]),
      SyncStage.saving => trNow(context, 'm0407'),
    };
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: AlertDialog(
      title: Text(tr(context, 'm0408')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LinearProgressIndicator(),
          const SizedBox(height: 16),
          Semantics(liveRegion: true, child: Text(_label)),
          const SizedBox(height: 8),
          Text(tr(context, 'm0409')),
        ],
      ),
    ),
  );
}
