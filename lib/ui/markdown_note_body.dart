import '../l10n/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'cached_markdown_image.dart';
import 'note_link_dialog.dart';
import 'markdown_math.dart';
import '../services/note_link_opener.dart';

Future<void> copyNoteText(BuildContext context, String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(trNow(context, 'm0161'))));
    }
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(trNow(context, 'm0162'))));
    }
  }
}

class MarkdownNoteBody extends StatelessWidget {
  const MarkdownNoteBody({
    required this.content,
    this.loadCachedImage,
    this.downloadImage,
    this.canDownloadImage,
    this.linkOpener,
    super.key,
  });

  final String content;
  final NoteLinkOpener? linkOpener;
  final CachedImageLoader? loadCachedImage;
  final Future<Uint8List> Function(Uri)? downloadImage;
  final bool Function(Uri)? canDownloadImage;

  @override
  Widget build(BuildContext context) => Markdown(
    data: content,
    inlineSyntaxes: [MathInlineSyntax()],
    blockSyntaxes: const [MathBlockSyntax()],
    builders: {
      'gemsnote-math': MathElementBuilder(),
      'gemsnote-math-block': MathElementBuilder(block: true),
    },
    selectable: true,
    padding: const EdgeInsets.all(20),
    // Media requires account-aware downloading; never resolve arbitrary local
    // paths or contact third-party hosts through the renderer's defaults.
    imageBuilder: (uri, title, alt) => loadCachedImage != null
        ? CachedMarkdownImage(
            uri: uri,
            alt: alt,
            load: loadCachedImage!,
            download:
                downloadImage != null && canDownloadImage?.call(uri) == true
                ? () => downloadImage!(uri)
                : null,
          )
        : Container(
            padding: const EdgeInsets.all(12),
            color: const Color(0xffebe8dc),
            child: Text(
              tr(context, 'm0163', [alt == null || alt.isEmpty ? '' : '：$alt']),
            ),
          ),
    onTapLink: (text, href, title) {
      if (href == null || href.isEmpty) return;
      showDialog<void>(
        context: context,
        builder: (dialogContext) => NoteLinkDialog(
          href: href,
          opener: linkOpener,
          onCopy: () => copyNoteText(dialogContext, href),
        ),
      );
    },
  );
}
