/// Search pane: full-text search across every markdown file in the open
/// folder, results grouped per file; clicking a match opens the file and
/// focuses the matching block.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../theme/theme_manager.dart';
import '../../workspace/file_io.dart';
import '../../workspace/workspace_controller.dart';

class SearchMatch {
  const SearchMatch(this.path, this.lineNumber, this.lineText);
  final String path;
  final int lineNumber; // 1-based
  final String lineText;
}

class SearchPane extends StatefulWidget {
  const SearchPane({super.key, required this.onOpenMatch});

  /// Opens [path] and reveals the match on [lineText].
  final void Function(String path, String lineText) onOpenMatch;

  @override
  State<SearchPane> createState() => _SearchPaneState();
}

class _SearchPaneState extends State<SearchPane> {
  final _query = TextEditingController();
  Timer? _debounce;
  int _epoch = 0;
  bool _searching = false;
  List<SearchMatch> _matches = const [];

  static const _maxMatches = 200;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  Future<void> _search() async {
    final workspace = context.read<WorkspaceController>();
    final root = workspace.folder;
    final needle = _query.text.trim().toLowerCase();
    final epoch = ++_epoch;
    if (root == null || needle.length < 2) {
      setState(() {
        _matches = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);

    final files = <FileTreeNode>[];
    void collect(List<FileTreeNode> nodes) {
      for (final n in nodes) {
        n.isDirectory ? collect(n.children) : files.add(n);
      }
    }

    collect(workspace.tree);
    final found = <SearchMatch>[];
    for (final file in files) {
      if (epoch != _epoch || found.length >= _maxMatches) break;
      final String text;
      try {
        text = await readTextFile(file.path);
      } catch (_) {
        continue;
      }
      final lines = text.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].toLowerCase().contains(needle)) {
          found.add(SearchMatch(file.path, i + 1, lines[i].trim()));
          if (found.length >= _maxMatches) break;
        }
      }
    }
    if (!mounted || epoch != _epoch) return;
    setState(() {
      _matches = found;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final workspace = context.watch<WorkspaceController>();
    final theme = context.watch<ThemeManager>().current;
    final fg = theme.sidebarForeground;

    // Group matches per file, preserving order.
    final groups = <String, List<SearchMatch>>{};
    for (final m in _matches) {
      groups.putIfAbsent(m.path, () => []).add(m);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: TextField(
            controller: _query,
            onChanged: _onQueryChanged,
            onSubmitted: (_) => _search(),
            style: TextStyle(fontSize: 13, color: theme.foreground),
            cursorColor: theme.caret,
            decoration: InputDecoration(
              isDense: true,
              hintText: workspace.folder == null
                  ? 'Open a folder to search'
                  : 'Search in folder…',
              hintStyle: TextStyle(fontSize: 13, color: theme.hintColor),
              prefixIcon: Icon(Icons.search, size: 16, color: fg),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: theme.hr),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: theme.accent),
              ),
            ),
          ),
        ),
        if (_searching)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text('Searching…',
                style: TextStyle(fontSize: 12, color: fg)),
          ),
        if (!_searching &&
            _matches.isEmpty &&
            _query.text.trim().length >= 2)
          Padding(
            padding: const EdgeInsets.all(8),
            child:
                Text('No matches', style: TextStyle(fontSize: 12, color: fg)),
          ),
        Expanded(
          child: ListView(
            children: [
              for (final entry in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                  child: Text(
                    p.basename(entry.key),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: theme.foreground.withValues(alpha: 0.8),
                    ),
                  ),
                ),
                for (final m in entry.value)
                  InkWell(
                    onTap: () => widget.onOpenMatch(m.path, m.lineText),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${m.lineNumber}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: fg.withValues(alpha: 0.7))),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              m.lineText,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: theme.foreground
                                      .withValues(alpha: 0.85)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              if (_matches.length >= _maxMatches)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('Showing the first $_maxMatches matches',
                      style: TextStyle(fontSize: 11, color: fg)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
