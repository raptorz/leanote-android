import 'dart:typed_data';

import 'package:flutter/material.dart';

typedef CachedImageLoader = Future<Uint8List?> Function(Uri uri);

class CachedMarkdownImage extends StatefulWidget {
  const CachedMarkdownImage({
    super.key,
    required this.uri,
    required this.alt,
    required this.load,
  });
  final Uri uri;
  final String? alt;
  final CachedImageLoader load;
  @override
  State<CachedMarkdownImage> createState() => _CachedMarkdownImageState();
}

class _CachedMarkdownImageState extends State<CachedMarkdownImage> {
  late Future<Uint8List?> _bytes;
  @override
  void initState() {
    super.initState();
    _bytes = widget.load(widget.uri);
  }

  @override
  void didUpdateWidget(CachedMarkdownImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri || oldWidget.load != widget.load) {
      _bytes = widget.load(widget.uri);
    }
  }

  Widget _placeholder() => Container(
    padding: const EdgeInsets.all(12),
    color: const Color(0xffebe8dc),
    child: Text(
      '图片尚未缓存或无法读取${widget.alt == null || widget.alt!.isEmpty ? '' : '：${widget.alt}'}',
    ),
  );
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _bytes,
    builder: (_, snapshot) {
      if (snapshot.connectionState != ConnectionState.done ||
          snapshot.hasError ||
          snapshot.data == null) {
        return _placeholder();
      }
      return Image(
        image: ResizeImage(
          MemoryImage(snapshot.data!),
          width: 2048,
          height: 2048,
          policy: ResizeImagePolicy.fit,
        ),
        semanticLabel: widget.alt,
        frameBuilder: (_, child, frame, _) =>
            frame == null ? _placeholder() : child,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    },
  );
}
