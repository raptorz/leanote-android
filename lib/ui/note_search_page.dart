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

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search(String value) async {
    final generation = ++_generation;
    final query = value.trim();
    final results = query.isEmpty
        ? const <Note>[]
        : await widget.repository.searchNotes(
            widget.session.account.cacheKey,
            query,
          );
    if (mounted && generation == _generation) {
      setState(() => _results = results);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: TextField(
        controller: _query,
        autofocus: true,
        onChanged: _search,
        decoration: const InputDecoration(
          hintText: '搜索笔记',
          border: InputBorder.none,
        ),
      ),
    ),
    body: _results.isEmpty
        ? Center(
            child: Text(_query.text.trim().isEmpty ? '输入关键词开始搜索' : '没有匹配的笔记'),
          )
        : ListView.separated(
            itemCount: _results.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
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
  );
}
