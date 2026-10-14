import '../l10n/app_strings.dart';

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
      title: Text(tr(context, 'm0410')),
      actions: [
        if (widget.session != null)
          IconButton(
            onPressed: _createTag,
            tooltip: tr(context, 'm0101'),
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
              child: Text(tr(context, 'm0411')),
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
                  labelText: tr(context, 'm0412'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _filter.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: tr(context, 'm0413'),
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(_filter.clear),
                        ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            CheckboxListTile(
              title: Text(tr(context, 'm0414')),
              value: _includeUnused,
              onChanged: (value) => setState(() {
                _includeUnused = value ?? false;
                _tags = _loadTags();
              }),
            ),
            if (!filtering && !_includeUnused && snapshot.data!.length > 10)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(tr(context, 'm0415')),
              ),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Text(
                        filtering
                            ? tr(context, 'm0416')
                            : _includeUnused
                            ? tr(context, 'm0417')
                            : tr(context, 'm0418'),
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
