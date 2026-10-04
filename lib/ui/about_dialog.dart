import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/api/api2_client.dart';

class MobileAboutDialog extends StatefulWidget {
  const MobileAboutDialog({super.key, this.loadPackageInfo});

  final Future<PackageInfo> Function()? loadPackageInfo;

  @override
  State<MobileAboutDialog> createState() => _MobileAboutDialogState();
}

class _MobileAboutDialogState extends State<MobileAboutDialog> {
  late Future<PackageInfo> _info = _load();

  Future<PackageInfo> _load() async =>
      await (widget.loadPackageInfo?.call() ?? PackageInfo.fromPlatform())
          .timeout(const Duration(seconds: 5));

  String _value(String value) => value.trim().isEmpty ? '未知' : value;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('关于珠玑笔记'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Image.asset(
              'assets/images/gemsnote_s.png',
              width: 64,
              height: 64,
            ),
          ),
          const SizedBox(height: 16),
          const Text('Gemsnote Mobile'),
          const Text('日积字句，终得珠玑。'),
          const SizedBox(height: 16),
          FutureBuilder<PackageInfo>(
            future: _info,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Text('正在读取应用版本…');
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('无法读取应用版本，请重试。'),
                    TextButton(
                      onPressed: () => setState(() {
                        _info = _load();
                      }),
                      child: const Text('重试'),
                    ),
                  ],
                );
              }
              final info = snapshot.data!;
              return SelectableText(
                '应用版本：${_value(info.version)}\n构建号：${_value(info.buildNumber)}',
              );
            },
          ),
          const Text('API2 协议版本：${Api2Client.clientVersion}'),
          const SizedBox(height: 16),
          const Text('基于 Leanote Android 重构，使用 Flutter 构建，支持本地 SQLite 离线缓存。'),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );
}
