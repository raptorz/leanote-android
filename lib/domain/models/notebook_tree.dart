import 'notebook.dart';

class NotebookTreeRow {
  const NotebookTreeRow(this.notebook, this.depth, this.hasChildren);
  final Notebook notebook;
  final int depth;
  final bool hasChildren;
}

/// Presentation-only tree. Malformed parent links are never written back.
class NotebookTree {
  NotebookTree(Iterable<Notebook> notebooks) {
    final sorted = notebooks.where((n) => !n.isDeleted).toList()
      ..sort((a, b) {
        final order = a.title.toLowerCase().compareTo(b.title.toLowerCase());
        return order != 0 ? order : a.notebookId.compareTo(b.notebookId);
      });
    final byId = {for (final n in sorted) n.notebookId: n};
    final parents = <String, String>{};
    for (final n in sorted) {
      parents[n.notebookId] =
          n.parentNotebookId != n.notebookId &&
              byId.containsKey(n.parentNotebookId)
          ? n.parentNotebookId
          : '';
    }
    // Break one edge per cycle in deterministic order, including disconnected
    // cycles. Orphans are roots, so every cached notebook remains reachable.
    final done = <String>{};
    for (final n in sorted) {
      final path = <String>{};
      var id = n.notebookId;
      while (id.isNotEmpty && !done.contains(id)) {
        if (!path.add(id)) {
          parents[id] = '';
          break;
        }
        id = parents[id] ?? '';
      }
      done.addAll(path);
    }
    for (final n in sorted) {
      (_children[parents[n.notebookId]!] ??= []).add(n);
    }
  }

  final _children = <String, List<Notebook>>{};

  List<NotebookTreeRow> visibleRows(Set<String> expanded) {
    final rows = <NotebookTreeRow>[];
    final stack = <(Notebook, int)>[
      for (final root in (_children[''] ?? <Notebook>[]).reversed) (root, 0),
    ];
    while (stack.isNotEmpty) {
      final (notebook, depth) = stack.removeLast();
      final children = _children[notebook.notebookId] ?? <Notebook>[];
      rows.add(NotebookTreeRow(notebook, depth, children.isNotEmpty));
      if (expanded.contains(notebook.notebookId)) {
        for (final child in children.reversed) {
          stack.add((child, depth + 1));
        }
      }
    }
    return rows;
  }
}
