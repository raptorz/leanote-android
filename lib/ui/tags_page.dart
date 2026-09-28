import 'package:flutter/material.dart';

import '../repositories/auth_repository.dart';

class TagsPage extends StatefulWidget {
  const TagsPage({
    required this.repository,
    required this.accountId,
    super.key,
  });

  final AuthRepository repository;
  final String accountId;

  @override
  State<TagsPage> createState() => _TagsPageState();
}

class _TagsPageState extends State<TagsPage> {
  late Future<Map<String, int>> _tags;

  @override
  void initState() {
    super.initState();
    _tags = widget.repository.tagCounts(widget.accountId);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('标签')),
    body: FutureBuilder<Map<String, int>>(
      future: _tags,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => setState(() {
                _tags = widget.repository.tagCounts(widget.accountId);
              }),
              child: const Text('读取标签失败，点击重试'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final entries = snapshot.data!.entries.toList();
        if (entries.isEmpty) return const Center(child: Text('暂无被笔记引用的标签'));
        return ListView.builder(
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
        );
      },
    ),
  );
}
