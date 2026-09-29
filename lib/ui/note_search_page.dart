import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/models/note.dart';
import '../repositories/auth_repository.dart';

class NoteSearchPage extends StatefulWidget {
  const NoteSearchPage({
    required this.repository,
    required this.session,
    super.key,
  });

  final AuthRepository repository;
  final StoredSession session;

  @override
  State<NoteSearchPage> createState() => _NoteSearchPageState();
}

class _NoteSearchPageState extends State<NoteSearchPage> {
  final _query = TextEditingController();
  List<Note> _results = const [];
  var _generation = 0;
  static const _pageSize = 50;
  var _limit = _pageSize;
  var _retryLimit = _pageSize;
  bool _busy = false;
  bool _hasMore = false;
  String? _error;
  Timer? _debounce;

  @override
  void dispose() {
    _query.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _queryChanged(String value) {
    _debounce?.cancel();
    final generation = ++_generation;
    setState(() {
      _results = [];
      _limit = _pageSize;
      _hasMore = false;
      _error = null;
      _busy = value.trim().isNotEmpty;
    });
    if (_busy) {
      _debounce = Timer(
        const Duration(milliseconds: 250),
        () => _search(generation),
      );
    }
  }

  Future<void> _search(int generation, {int? limit}) async {
    final requested = limit ?? _limit;
    setState(() {
      _busy = true;
      _error = null;
      _retryLimit = requested;
    });
    try {
      // Re-read the growing prefix rather than append offsets: concurrent
      // syncs or edits must not duplicate/skip rows across page boundaries.
      final results = await widget.repository.searchNotes(
        widget.session.account.cacheKey,
        _query.text.trim(),
        limit: requested + 1,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _limit = requested;
        _hasMore = results.length > requested;
        _results = results.take(requested).toList();
      });
    } on Object catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = '搜索失败：$error');
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: TextField(
        controller: _query,
        autofocus: true,
        onChanged: _queryChanged,
        decoration: const InputDecoration(
          hintText: '搜索笔记',
          border: InputBorder.none,
        ),
      ),
    ),
    body: Column(
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          ListTile(
            title: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            trailing: TextButton(
              onPressed: _busy
                  ? null
                  : () => _search(_generation, limit: _retryLimit),
              child: const Text('重试'),
            ),
          ),
        if (_results.isNotEmpty)
          Text('已显示 ${_results.length} 篇${_hasMore ? '，还有更多结果' : ''}'),
        Expanded(
          child: _results.isEmpty
              ? Center(
                  child: Text(
                    _query.text.trim().isEmpty
                        ? '输入关键词开始搜索'
                        : _busy
                        ? '正在搜索…'
                        : _error != null
                        ? '请重试搜索'
                        : '没有匹配的笔记',
                  ),
                )
              : ListView.separated(
                  itemCount: _results.length + (_hasMore ? 1 : 0),
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    if (index == _results.length) {
                      return TextButton(
                        onPressed: _busy
                            ? null
                            : () => _search(
                                _generation,
                                limit: _limit + _pageSize,
                              ),
                        child: const Text('加载更多'),
                      );
                    }
                    final note = _results[index];
                    return ListTile(
                      leading: Icon(
                        note.isMarkdown ? Icons.code : Icons.article_outlined,
                      ),
                      title: Text(
                        note.title.isEmpty ? '无标题' : note.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(note.updatedTime, maxLines: 1),
                      onTap: () => Navigator.pop(context, note),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}
