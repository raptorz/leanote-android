import 'package:flutter/material.dart';

import '../repositories/auth_repository.dart';
import '../domain/models/tag_choices.dart';
import 'create_tag_dialog.dart';

class TagsPage extends StatefulWidget {
  const TagsPage({
    required this.repository,
    required this.accountId,
    this.session,
    super.key,
  });

  final AuthRepository repository;
  final String accountId;
  final StoredSession? session;

  @override
  State<TagsPage> createState() => _TagsPageState();
}

class _TagsPageState extends State<TagsPage> {
  late Future<Map<String, int>> _tags;
  final _filter = TextEditingController();
  bool _includeUnused = false;

  Future<Map<String, int>> _loadTags() => _includeUnused
      ? widget.repository.availableTags(widget.accountId)
      : widget.repository.tagCounts(widget.accountId);

  Future<void> _createTag() async {
    final session = widget.session;
    if (session == null || session.account.cacheKey != widget.accountId) return;
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CreateTagDialog(
        onCreate: (name) => widget.repository.createTag(session, name),
      ),
    );
    if (created == true && mounted) {
      setState(() {
        _includeUnused = true;
        _filter.clear();
        _tags = _loadTags();
      });
    }
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _tags = _loadTags();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('标签'),
      actions: [
        if (widget.session != null)
          IconButton(
            onPressed: _createTag,
            tooltip: '创建标签',
            icon: const Icon(Icons.add),
          ),
      ],
    ),
    body: FutureBuilder<Map<String, int>>(
      future: _tags,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => setState(() {
                _tags = _loadTags();
              }),
              child: const Text('读取标签失败，点击重试'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final filtering = _filter.text.trim().isNotEmpty;
        final entries = tagChoices(
          snapshot.data!,
          query: _filter.text,
          limit: filtering || _includeUnused ? null : 10,
          includeUnused: _includeUnused,
        );
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _filter,
                decoration: InputDecoration(
                  labelText: '过滤标签',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _filter.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清空过滤',
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(_filter.clear),
                        ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            CheckboxListTile(
              title: const Text('显示未使用标签'),
              value: _includeUnused,
              onChanged: (value) => setState(() {
                _includeUnused = value ?? false;
                _tags = _loadTags();
              }),
            ),
            if (!filtering && !_includeUnused && snapshot.data!.length > 10)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('显示笔记最多的 10 个标签，其他请过滤查找'),
              ),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Text(
                        filtering
                            ? '没有匹配的标签'
                            : _includeUnused
                            ? '暂无标签'
                            : '暂无被笔记引用的标签',
                      ),
                    )
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final tag = entries[index];
                        return ListTile(
                          leading: const Icon(Icons.label_outline),
                          title: Text(
                            tag.key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text('${tag.value}'),
                          onTap: () => Navigator.of(context).pop(tag.key),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    ),
  );
}
