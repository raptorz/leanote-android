import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'editor_link_dialog.dart';
import 'visual_html_policy.dart';
export 'visual_html_policy.dart' show supportsVisualHtml;

String visualEditorDocument(String source) {
  if (!supportsVisualHtml(source)) {
    throw ArgumentError('Unsupported rich text');
  }
  // JSON + escaping '<' prevents a note from closing the inline script.
  final initial = jsonEncode(source).replaceAll('<', r'\u003c');
  return '''<!doctype html><html><head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'none'; img-src 'none'; form-action 'none'; base-uri 'none'">
<style>body{font:17px sans-serif;margin:16px;line-height:1.6;color:#183c32}
#editor{min-height:80vh;outline:none;overflow-wrap:anywhere}
blockquote{border-left:3px solid #527b68;margin-left:0;padding-left:12px}</style>
</head><body><div id="editor" contenteditable="true"></div><script>
const editor = document.getElementById('editor');
const original = $initial;
editor.innerHTML = original;
let changed = false;
let savedRange = null;
document.addEventListener('selectionchange', () => {
  const selection = window.getSelection();
  if (selection.rangeCount && editor.contains(selection.anchorNode) && editor.contains(selection.focusNode)) {
    savedRange = selection.getRangeAt(0).cloneRange();
  }
});
function restoreSelection() {
  editor.focus();
  if (savedRange && editor.contains(savedRange.commonAncestorContainer)) {
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(savedRange);
  }
}
function publish() { changed = true; Changes.postMessage(editor.innerHTML); }
editor.addEventListener('input', publish);
editor.addEventListener('paste', event => {
  event.preventDefault();
  document.execCommand('insertText', false, event.clipboardData.getData('text/plain'));
});
editor.addEventListener('drop', event => event.preventDefault());
document.addEventListener('click', event => {
  if (event.target.closest('a')) event.preventDefault();
});
window.readContent = () => changed ? editor.innerHTML : original;
window.format = (command, value) => {
  const allowed = ['bold','italic','underline','insertUnorderedList','insertOrderedList','formatBlock','undo','redo','unlink'];
  if (!allowed.includes(command)) return;
  restoreSelection();
  document.execCommand('styleWithCSS', false, false);
  document.execCommand(command, false, value);
  publish();
};
window.insertLink = value => {
  restoreSelection();
  const selection = window.getSelection();
  if (!selection.rangeCount || !editor.contains(selection.anchorNode)) return;
  if (selection.isCollapsed) {
    const link = document.createElement('a');
    link.href = value;
    link.textContent = value;
    document.execCommand('insertHTML', false, link.outerHTML);
  } else {
    document.execCommand('createLink', false, value);
  }
  publish();
};
</script></body></html>''';
}

class VisualHtmlEditor extends StatefulWidget {
  const VisualHtmlEditor({
    required this.source,
    required this.onChanged,
    super.key,
  });

  final String source;
  final ValueChanged<String> onChanged;

  @override
  State<VisualHtmlEditor> createState() => _VisualHtmlEditorState();
}

class _VisualHtmlEditorState extends State<VisualHtmlEditor> {
  late final WebViewController _controller;
  bool _ready = false;
  bool _leaving = false;
  bool _allowPop = false;
  bool _linkDialogOpen = false;
  String? _error;
  Completer<String>? _snapshot;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'Changes',
        onMessageReceived: (message) {
          if (mounted) _accept(message.message);
        },
      )
      ..addJavaScriptChannel(
        'Snapshot',
        onMessageReceived: (message) {
          final pending = _snapshot;
          if (pending != null && !pending.isCompleted) {
            pending.complete(message.message);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) =>
              !_ready && request.url == 'about:blank'
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onPageFinished: (_) {
            if (mounted) setState(() => _ready = true);
          },
          onWebResourceError: (error) {
            if (mounted) {
              setState(() => _error = '编辑器加载失败：${error.description}');
            }
          },
        ),
      );
    _load();
  }

  Future<void> _load() async {
    try {
      await _controller.loadHtmlString(visualEditorDocument(widget.source));
    } catch (error) {
      if (mounted) setState(() => _error = '编辑器加载失败：$error');
    }
  }

  bool _accept(String value) {
    if (!supportsVisualHtml(value)) {
      setState(() => _error = '当前排版超出支持范围，请撤销后重试；未覆盖本地原文。');
      return false;
    }
    widget.onChanged(value);
    setState(() => _error = null);
    return true;
  }

  Future<void> _close() async {
    if (_leaving) return;
    if (!_ready) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _leaving = true);
    try {
      final pending = Completer<String>();
      _snapshot = pending;
      await _controller
          .runJavaScript('Snapshot.postMessage(window.readContent())')
          .timeout(const Duration(seconds: 5));
      final content = await pending.future.timeout(const Duration(seconds: 5));
      if (!mounted) return;
      if (!_accept(content)) return;
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    } catch (error) {
      if (mounted) setState(() => _error = '读取编辑内容失败，请重试：$error');
    } finally {
      _snapshot = null;
      if (mounted) setState(() => _leaving = false);
    }
  }

  Future<void> _insertLink() async {
    if (_linkDialogOpen || !_ready || _leaving) return;
    setState(() => _linkDialogOpen = true);
    try {
      final value = await showDialog<String>(
        context: context,
        builder: (_) => const EditorLinkDialog(),
      );
      if (!mounted || value == null) return;
      if (!isSafeEditorLink(value)) return;
      await _controller.runJavaScript(
        'window.insertLink(${jsonEncode(value)})',
      );
    } catch (error) {
      if (mounted) setState(() => _error = '插入链接失败：$error');
    } finally {
      if (mounted) setState(() => _linkDialogOpen = false);
    }
  }

  Widget _button(
    String label,
    IconData icon,
    String command, [
    String? value,
  ]) => IconButton(
    tooltip: label,
    icon: Icon(icon),
    onPressed: !_ready || _leaving
        ? null
        : () async {
            try {
              await _controller.runJavaScript(
                'window.format(${jsonEncode(command)}, ${jsonEncode(value)})',
              );
            } catch (error) {
              if (mounted) setState(() => _error = '排版失败：$error');
            }
          },
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop || !_ready,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _close();
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('可视化编辑'),
        actions: [
          IconButton(
            tooltip: '完成',
            onPressed: _leaving ? null : _close,
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              actions: [TextButton(onPressed: _close, child: const Text('重试'))],
            ),
          if (!_ready) const LinearProgressIndicator(),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _button('撤销', Icons.undo, 'undo'),
                _button('重做', Icons.redo, 'redo'),
                _button('加粗', Icons.format_bold, 'bold'),
                _button('斜体', Icons.format_italic, 'italic'),
                _button('下划线', Icons.format_underlined, 'underline'),
                _button('标题', Icons.title, 'formatBlock', 'h2'),
                _button('正文', Icons.notes, 'formatBlock', 'p'),
                _button('引用', Icons.format_quote, 'formatBlock', 'blockquote'),
                IconButton(
                  tooltip: '插入链接',
                  icon: const Icon(Icons.link),
                  onPressed: !_ready || _leaving || _linkDialogOpen
                      ? null
                      : _insertLink,
                ),
                _button('移除链接', Icons.link_off, 'unlink'),
                _button(
                  '无序列表',
                  Icons.format_list_bulleted,
                  'insertUnorderedList',
                ),
                _button(
                  '有序列表',
                  Icons.format_list_numbered,
                  'insertOrderedList',
                ),
              ],
            ),
          ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    ),
  );
}
