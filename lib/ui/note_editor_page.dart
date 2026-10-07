import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/models/note.dart';
import 'cached_markdown_image.dart';
import 'markdown_editing.dart';
import 'markdown_note_body.dart';
import 'safe_html_note_body.dart';
import 'visual_html_editor.dart';
import 'editor_link_dialog.dart';
import '../services/note_image_picker.dart';
import 'note_image_upload_dialog.dart';

class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({
    required this.note,
    required this.saveText,
    this.loadCachedImage,
    this.uploadImage,
    this.pickImage,
    this.identity = '',
    super.key,
  });

  final Note note;
  final String identity;
  final Future<NoteImageUpload?> Function()? pickImage;
  final Future<String> Function(
    NoteImageUpload image,
    String identity,
    String password,
  )?
  uploadImage;
  final Future<void> Function(String title, String content) saveText;
  // Preview is cache-only: editing arbitrary image URLs must never fetch them.
  final CachedImageLoader? loadCachedImage;

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage>
    with WidgetsBindingObserver {
  late final TextEditingController _title;
  late final TextEditingController _content;
  var _allowPop = false;
  var _closing = false;
  Timer? _debounce;
  Future<bool>? _saving;
  late String _savedTitle;
  late String _savedContent;
  final _saveError = ValueNotifier<String?>(null);
  String? get _error => _saveError.value;
  bool _preview = false;
  final _contentFocus = FocusNode();
  final _titleFocus = FocusNode();
  final _titleUndo = UndoHistoryController();
  final _contentUndo = UndoHistoryController();
  bool _editingTitle = false;
  bool _linkDialogOpen = false;
  bool _insertingImage = false;
  bool get _busy => _closing || _insertingImage;

  @override
  void initState() {
    super.initState();
    // A valid initial selection lets Flutter record the original text before
    // the first edit (including a toolbar edit made before the field is focused).
    _title = TextEditingController.fromValue(
      TextEditingValue(
        text: widget.note.title,
        selection: TextSelection.collapsed(offset: widget.note.title.length),
      ),
    );
    _content = TextEditingController.fromValue(
      TextEditingValue(
        text: widget.note.content,
        selection: TextSelection.collapsed(offset: widget.note.content.length),
      ),
    );
    _savedTitle = widget.note.title;
    _savedContent = widget.note.content;
    _title.addListener(_changed);
    _content.addListener(_changed);
    _titleFocus.addListener(_trackFocus);
    _contentFocus.addListener(_trackFocus);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _contentFocus.dispose();
    _titleFocus.dispose();
    _titleUndo.dispose();
    _contentUndo.dispose();
    _title.dispose();
    _content.dispose();
    _saveError.dispose();
    super.dispose();
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _flush);
  }

  void _trackFocus() {
    if (_titleFocus.hasFocus || _contentFocus.hasFocus) {
      setState(() => _editingTitle = _titleFocus.hasFocus);
    }
  }

  Widget _historyButtons() {
    final history = _editingTitle ? _titleUndo : _contentUndo;
    return ValueListenableBuilder<UndoHistoryValue>(
      valueListenable: history,
      builder: (_, value, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '撤销',
            onPressed: !_busy && value.canUndo ? history.undo : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: '重做',
            onPressed: !_busy && value.canRedo ? history.redo : null,
            icon: const Icon(Icons.redo),
          ),
        ],
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _flush();
  }

  Future<bool> _flush() {
    _debounce?.cancel();
    return _saving ??= _drain().whenComplete(() => _saving = null);
  }

  Future<bool> _drain() async {
    while (mounted) {
      final title = _title.text;
      final content = _content.text;
      if (title == _savedTitle && content == _savedContent) return true;
      try {
        await widget.saveText(title, content);
        _savedTitle = title;
        _savedContent = content;
        if (mounted) setState(() => _saveError.value = null);
      } on Object catch (error) {
        if (mounted) setState(() => _saveError.value = '保存到本地失败：$error');
        return false;
      }
    }
    return false;
  }

  Future<void> _save() async {
    if (_allowPop || _busy) return;
    setState(() => _closing = true);
    final saved = await _flush();
    if (!mounted) return;
    if (!saved) {
      setState(() => _closing = false);
      return;
    }
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _togglePreview() {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _preview = !_preview);
    _flush();
  }

  Future<void> _insertMarkdownLink() async {
    if (_busy || _linkDialogOpen) return;
    final original = _content.value;
    setState(() => _linkDialogOpen = true);
    try {
      final url = await showDialog<String>(
        context: context,
        builder: (_) => const EditorLinkDialog(),
      );
      if (!mounted || url == null) return;
      if (_content.text != original.text) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('正文已变化，请重新选择文字后插入链接。')));
        return;
      }
      _content.value = insertMarkdownLink(original, url);
      _contentFocus.requestFocus();
    } finally {
      if (mounted) setState(() => _linkDialogOpen = false);
    }
  }

  Future<void> _insertImage() async {
    if (_busy || widget.uploadImage == null) return;
    final original = _content.value;
    setState(() => _insertingImage = true);
    try {
      final image = await (widget.pickImage ?? NoteImagePicker().pick)();
      if (!mounted || image == null) return;
      if (!await _flush() || !mounted) return;
      final reference = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => NoteImageUploadDialog(
          identity: widget.identity,
          image: image,
          upload: (identity, password) =>
              widget.uploadImage!(image, identity, password),
        ),
      );
      if (!mounted || reference == null) return;
      // Only API-created relative references may be written into the body.
      if (!RegExp(r'^/api2/file/getImage\?fileId=[0-9a-fA-F]{24}$')
          .hasMatch(reference)) {
        throw const FormatException('图片地址无效，未插入正文');
      }
      // Insert after the selection, preserving selected text and all HTML.
      // HTML images are appended so a caret inside a tag cannot corrupt it.
      final offset =
          widget.note.isMarkdown &&
              _content.text == original.text &&
              original.selection.isValid
          ? original.selection.end.clamp(0, _content.text.length)
          : _content.text.length;
      final markup = widget.note.isMarkdown
          ? '\n![]($reference)\n'
          : '\n<img src="$reference" alt="">\n';
      _content.value = TextEditingValue(
        text: _content.text.replaceRange(offset, offset, markup),
        selection: TextSelection.collapsed(offset: offset + markup.length),
      );
      final saved = await _flush();
      if (mounted && saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('图片已插入并保存到本地，正文待同步。同步后可在阅读页下载预览图片。')),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('插入图片失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _insertingImage = false);
    }
  }

  Widget _formatButton(
    String label,
    IconData icon,
    TextEditingValue Function(TextEditingValue) transform,
  ) => IconButton(
    tooltip: label,
    icon: Icon(icon),
    onPressed: _busy
        ? null
        : () {
            _content.value = transform(_content.value);
            _contentFocus.requestFocus();
          },
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.note.isMarkdown ? '编辑 Markdown' : '编辑 HTML 原文'),
      actions: [
        if (!widget.note.isMarkdown)
          IconButton(
            tooltip: '可视化编辑',
            icon: const Icon(Icons.format_shapes),
            onPressed: _busy
                ? null
                : () async {
                    if (!supportsVisualHtml(_content.text)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            '此笔记包含图片、不支持的链接或复杂 HTML，请继续编辑原文，避免丢失内容。',
                          ),
                        ),
                      );
                      return;
                    }
                    _contentFocus.unfocus();
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => VisualHtmlEditor(
                          source: _content.text,
                          flush: _flush,
                          saveError: _saveError,
                          onChanged: (value) {
                            _content.text = value;
                          },
                        ),
                      ),
                    );
                    if (mounted) await _flush();
                  },
          ),
        IconButton(
          tooltip: _preview
              ? '继续编辑'
              : widget.note.isMarkdown
              ? '预览 Markdown'
              : '预览富文本',
          onPressed: _busy ? null : _togglePreview,
          icon: Icon(
            _preview ? Icons.edit_outlined : Icons.visibility_outlined,
          ),
        ),
        IconButton(
          tooltip: '保存到本地',
          onPressed: _busy ? null : _save,
          icon: const Icon(Icons.check),
        ),
      ],
    ),
    body: PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _save();
      },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_error != null)
              MaterialBanner(
                content: Text(_error!),
                actions: [
                  TextButton(onPressed: _flush, child: const Text('重试')),
                ],
              ),
            TextField(
              focusNode: _titleFocus,
              undoController: _titleUndo,
              readOnly: _busy,
              controller: _title,
              autofocus: widget.note.title.isEmpty,
              decoration: const InputDecoration(hintText: '笔记标题'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (!widget.note.isMarkdown)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('编辑 HTML 原文，预览显示基本排版及已缓存图片，不联网加载资源或执行脚本。原文将完整保存。'),
              ),
            if (!_preview)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _historyButtons(),
                    if (widget.uploadImage != null)
                      IconButton(
                        tooltip: widget.note.isMarkdown ? '插入图片' : '在文末插入图片',
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        onPressed: _busy ? null : _insertImage,
                      ),
                    if (widget.note.isMarkdown) ...[
                      _formatButton(
                        '加粗',
                        Icons.format_bold,
                        (value) => wrapMarkdown(value, '**'),
                      ),
                      _formatButton(
                        '斜体',
                        Icons.format_italic,
                        (value) => wrapMarkdown(value, '*'),
                      ),
                      _formatButton(
                        '行内代码',
                        Icons.code,
                        (value) => wrapMarkdown(value, '`'),
                      ),
                      _formatButton(
                        '标题',
                        Icons.title,
                        (value) => prefixMarkdownLines(value, '# '),
                      ),
                      _formatButton(
                        '无序列表',
                        Icons.format_list_bulleted,
                        (value) => prefixMarkdownLines(value, '- '),
                      ),
                      _formatButton(
                        '有序列表',
                        Icons.format_list_numbered,
                        numberMarkdownLines,
                      ),
                      _formatButton(
                        '引用',
                        Icons.format_quote,
                        (value) => prefixMarkdownLines(value, '> '),
                      ),
                      _formatButton(
                        '删除线',
                        Icons.format_strikethrough,
                        (value) => wrapMarkdown(value, '~~'),
                      ),
                      _formatButton(
                        '代码块',
                        Icons.code_outlined,
                        fenceMarkdownCode,
                      ),
                      IconButton(
                        tooltip: '插入链接',
                        icon: const Icon(Icons.link),
                        onPressed: _busy || _linkDialogOpen
                            ? null
                            : _insertMarkdownLink,
                      ),
                    ],
                  ],
                ),
              ),
            Expanded(
              child: IndexedStack(
                index: _preview ? 1 : 0,
                sizing: StackFit.expand,
                children: [
                  TextField(
                    undoController: _contentUndo,
                    focusNode: _contentFocus,
                    readOnly: _busy,
                    controller: _content,
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      hintText: widget.note.isMarkdown
                          ? '使用 Markdown 开始记录…'
                          : '输入 HTML 原文，例如 <p>开始记录…</p>',
                      border: InputBorder.none,
                    ),
                  ),
                  if (_preview)
                    widget.note.isMarkdown
                        ? MarkdownNoteBody(
                            content: _content.text,
                            loadCachedImage: widget.loadCachedImage,
                          )
                        : SafeHtmlNoteBody(
                            content: _content.text,
                            loadCachedImage: widget.loadCachedImage,
                          )
                  else
                    const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
