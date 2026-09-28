import 'package:flutter/material.dart';

Future<bool> confirmResetSync(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('重新同步当前账号？'),
        content: const Text(
          '将用服务端数据替换当前账号的本地笔记、笔记本和标签，未上传的修改将被丢弃，不会先上传。其他账号的数据不受影响。\n\n下载失败时保留原缓存；下载成功后替换不可撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认重新同步'),
          ),
        ],
      ),
    ) ??
    false;
