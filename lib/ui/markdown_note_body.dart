import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

Future<void> copyNoteText(BuildContext context, String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已复制')));
    }
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('复制失败，请重试')));
    }
  }
}

class MarkdownNoteBody extends StatelessWidget {
  const MarkdownNoteBody({required this.content, super.key});

  final String content;

  @override
  Widget build(BuildContext context) => Markdown(
    data: content,
    selectable: true,
    padding: const EdgeInsets.all(20),
    // Media requires account-aware downloading; never resolve arbitrary local
    // paths or contact third-party hosts through the renderer's defaults.
    imageBuilder: (uri, title, alt) => Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xffebe8dc),
      child: Text('图片尚未缓存${alt == null || alt.isEmpty ? '' : '：$alt'}'),
    ),
    onTapLink: (text, href, title) {
      if (href == null || href.isEmpty) return;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('链接地址'),
          content: SingleChildScrollView(child: SelectableText(href)),
          actions: [
            TextButton(
              onPressed: () => copyNoteText(context, href),
              child: const Text('复制链接'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    },
  );
}
