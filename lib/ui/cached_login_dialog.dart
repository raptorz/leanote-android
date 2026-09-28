import 'package:flutter/material.dart';

Future<bool> chooseCachedLoginReset(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('发现此账号的本地缓存'),
          content: const Text(
            '不同步：保留本地笔记和未上传修改，登录后可手动同步。\n\n重新同步：用服务端数据替换当前账号缓存，未上传修改将被丢弃，不会先上传。下载失败时保留原缓存。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('不同步'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('重新同步'),
            ),
          ],
        ),
      ),
    ) ??
    false;
