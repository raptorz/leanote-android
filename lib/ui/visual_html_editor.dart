import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'editor_link_dialog.dart';
import 'editor_table_dialog.dart';
import 'editor_table_operations.dart';
import 'editor_save_guard.dart';
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
blockquote{border-left:3px solid #527b68;margin-left:0;padding-left:12px}
table{border-collapse:collapse;max-width:100%;table-layout:fixed;width:100%}
td,th{border:1px solid #527b68;padding:6px;min-width:24px;overflow-wrap:anywhere}
th{background:#e5eee8}caption{font-weight:bold}</style>
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
window.insertTable = value => {
  restoreSelection();
  const selection = window.getSelection();
  if (!selection.rangeCount || !editor.contains(selection.anchorNode)) return;
  const anchor = selection.anchorNode.nodeType === Node.ELEMENT_NODE
    ? selection.anchorNode : selection.anchorNode.parentElement;
  if (anchor.closest('table')) {
    EditorError.postMessage('请先将光标移到表格外，避免嵌套表格');
    return;
  }
  document.execCommand('insertHTML', false, value);
  publish();
};
let pendingTable = null;
window.selectedTable = id => {
  restoreSelection();
  const selection = window.getSelection();
  const node = selection.anchorNode;
  const element = node && (node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement);
  const cell = element && element.closest('td,th');
  const table = cell && cell.closest('table');
  pendingTable = table && editor.contains(table) ? {id, table} : null;
  return pendingTable ? {id, html: table.outerHTML, row: Array.from(table.querySelectorAll('tr')).indexOf(cell.parentElement), column: cell.cellIndex} : {id};
};
window.replaceTable = (id, expected, replacement) => {
  const target = pendingTable;
  pendingTable = null;
  if (!target || target.id !== id || !editor.contains(target.table) || target.table.outerHTML !== expected) {
    EditorError.postMessage('表格已变化，请重新选择单元格后重试');
    return;
  }
  editor.focus();
  const range = document.createRange();
  range.selectNode(target.table);
  const selection = window.getSelection();
  selection.removeAllRanges();
  selection.addRange(range);
  document.execCommand('insertHTML', false, replacement);
  publish();
};
</script></body></html>''';
}

class VisualHtmlEditor extends StatefulWidget {
  const VisualHtmlEditor({
    required this.source,
    required this.onChanged,
    required this.flush,
    required this.saveError,
    super.key,
  });

  final String source;
  final ValueChanged<String> onChanged;
  final Future<bool> Function() flush;
  final ValueListenable<String?> saveError;

  @override
  State<VisualHtmlEditor> createState() => _VisualHtmlEditorState();
}

class _VisualHtmlEditorState extends State<VisualHtmlEditor> {
  late final WebViewController _controller;
  bool _ready = false;
  bool _leaving = false;
  bool _allowPop = false;
  bool _dialogOpen = false;
  String? _error;
  Completer<String>? _snapshot;
  Completer<Map<String, dynamic>>? _tableSnapshot;
  int _tableRequest = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'TableSelection',
        onMessageReceived: (message) {
          final pending = _tableSnapshot;
          if (pending == null || pending.isCompleted) return;
          try {
            final value = jsonDecode(message.message) as Map<String, dynamic>;
            if (value['id'] == _tableRequest) pending.complete(value);
          } catch (error) {
            pending.completeError(error);
          }
        },
      )
      ..addJavaScriptChannel(
        'EditorError',
        onMessageReceived: (message) {
          if (mounted) setState(() => _error = message.message);
        },
      )
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
    setState(() => _leaving = true);
    try {
      final saved = await persistVisualEdit(
        read: () async {
          if (!_ready) return null;
          final pending = Completer<String>();
          _snapshot = pending;
          final result = pending.future.timeout(const Duration(seconds: 5));
          unawaited(
            _controller
                .runJavaScript(
                  'editor.contentEditable = "false"; editor.blur(); Snapshot.postMessage(window.readContent())',
                )
                .catchError((Object error) {
                  if (!pending.isCompleted) pending.completeError(error);
                }),
          );
          return result;
        },
        accept: (value) => mounted && _accept(value),
        flush: widget.flush,
      );
      if (!mounted || !saved) return;
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    } catch (error) {
      if (mounted) setState(() => _error = '读取或保存编辑内容失败，请重试：$error');
    } finally {
      _snapshot = null;
      if (mounted && _ready && !_allowPop) {
        try {
          await _controller.runJavaScript('editor.contentEditable = "true"');
        } catch (error) {
          if (mounted) setState(() => _error = '恢复编辑失败：$error');
        }
      }
      if (mounted) setState(() => _leaving = false);
    }
  }

  Future<void> _insertLink() async {
    if (_dialogOpen || !_ready || _leaving) return;
    setState(() => _dialogOpen = true);
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
      if (mounted) setState(() => _dialogOpen = false);
    }
  }

  Future<void> _insertTable() async {
    if (_dialogOpen || !_ready || _leaving) return;
    setState(() => _dialogOpen = true);
    try {
      final value = await showDialog<String>(
        context: context,
        builder: (_) => const EditorTableDialog(),
      );
      if (!mounted || value == null) return;
      if (!supportsVisualHtml(value)) return;
      await _controller.runJavaScript(
        'window.insertTable(${jsonEncode(value)})',
      );
    } catch (error) {
      if (mounted) setState(() => _error = '插入表格失败：$error');
    } finally {
      if (mounted) setState(() => _dialogOpen = false);
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
    onPressed: !_ready || _leaving || _dialogOpen
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

  Future<void> _changeTable(TableOperation operation) async {
    if (!_ready || _leaving || _dialogOpen) return;
    setState(() => _dialogOpen = true);
    try {
      final pending = Completer<Map<String, dynamic>>();
      _tableSnapshot = pending;
      final id = ++_tableRequest;
      // Install timeout before dispatching, including native dispatch failures.
      final response = pending.future.timeout(const Duration(seconds: 5));
      unawaited(
        _controller
            .runJavaScript(
              'TableSelection.postMessage(JSON.stringify(window.selectedTable($id)))',
            )
            .catchError((Object error) {
              if (!pending.isCompleted) pending.completeError(error);
            }),
      );
      final snapshot = await response;
      if (!mounted) return;
      if (snapshot['html'] == null) throw const FormatException('请先点击表格中的单元格');
      final original = snapshot['html'] as String;
      final replacement = changeEditorTable(
        original,
        snapshot['row'] as int,
        snapshot['column'] as int,
        operation,
      );
      if (operation == TableOperation.removeRow ||
          operation == TableOperation.removeColumn) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              operation == TableOperation.removeRow ? '删除当前行？' : '删除当前列？',
            ),
            content: const Text('所选行或列中的内容也会删除。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除'),
              ),
            ],
          ),
        );
        if (!mounted || confirmed != true) return;
      }
      await _controller.runJavaScript(
        'window.replaceTable($id, ${jsonEncode(original)}, ${jsonEncode(replacement)})',
      );
    } catch (error) {
      if (mounted) setState(() => _error = '表格操作失败：$error');
    } finally {
      _tableSnapshot = null;
      if (mounted) setState(() => _dialogOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop,
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
          EditorSaveBanner(error: widget.saveError, retry: widget.flush),
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
                  onPressed: !_ready || _leaving || _dialogOpen
                      ? null
                      : _insertLink,
                ),
                _button('移除链接', Icons.link_off, 'unlink'),
                PopupMenuButton<TableOperation>(
                  tooltip: '表格行列操作',
                  enabled: _ready && !_leaving && !_dialogOpen,
                  icon: const Icon(Icons.table_rows_outlined),
                  onSelected: _changeTable,
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: TableOperation.addRow,
                      child: Text('下方插入行'),
                    ),
                    PopupMenuItem(
                      value: TableOperation.addColumn,
                      child: Text('右侧插入列'),
                    ),
                    PopupMenuItem(
                      value: TableOperation.removeRow,
                      child: Text('删除当前行'),
                    ),
                    PopupMenuItem(
                      value: TableOperation.removeColumn,
                      child: Text('删除当前列'),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: '插入表格',
                  icon: const Icon(Icons.table_chart_outlined),
                  onPressed: !_ready || _leaving || _dialogOpen
                      ? null
                      : _insertTable,
                ),
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
