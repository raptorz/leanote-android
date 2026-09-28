import 'package:flutter/material.dart';

Future<bool> confirmUnsyncedLogout(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('仍有未同步的修改'),
        content: const Text('退出前上传未完成，是否不同步退出？本地数据将保留，下次登录同一服务器的同一用户后可继续同步。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('不同步退出'),
          ),
        ],
      ),
    ) ??
    false;
