/// Open Quickly: a fuzzy-matching command palette over the open folder's
/// files and the recent-files list. Keyboard-driven.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../theme/theme_manager.dart';
import '../workspace/file_io.dart';
import '../workspace/workspace_controller.dart';

/// Case-insensitive subsequence match; returns a score (lower = better) or
/// null if [query] is not a subsequence of [text]. Consecutive and
/// word-start matches score better. Exposed for testing.
@visibleForTesting
int? fuzzyScore(String query, String text) => _fuzzyScore(query, text);

int? _fuzzyScore(String query, String text) {
  if (query.isEmpty) return 0;
  final q = query.toLowerCase();
  final t = text.toLowerCase();
  var qi = 0;
  var score = 0;
  var lastMatch = -2;
  for (var ti = 0; ti < t.length && qi < q.length; ti++) {
    if (t[ti] == q[qi]) {
      score += ti; // earlier matches score better
      if (ti == lastMatch + 1) score -= 3; // reward runs
      if (ti == 0 || !RegExp(r'[a-z0-9]').hasMatch(t[ti - 1])) {
        score -= 5; // reward word-start matches
      }
      lastMatch = ti;
      qi++;
    }
  }
  return qi == q.length ? score : null;
}

class _Candidate {
  const _Candidate(this.path, this.name);
  final String path;
  final String name;
}

/// Shows the Open Quickly palette; returns the chosen file path or null.
Future<String?> showOpenQuickly(
  BuildContext context, {
  required WorkspaceController workspace,
  required ThemeManager themeManager,
}) {
  final candidates = <_Candidate>[];
  final seen = <String>{};
  void add(String path) {
    if (seen.add(path)) candidates.add(_Candidate(path, p.basename(path)));
  }

  void collect(List<FileTreeNode> nodes) {
    for (final n in nodes) {
      n.isDirectory ? collect(n.children) : add(n.path);
    }
  }

  collect(workspace.tree);
  for (final r in workspace.recentFiles) {
    add(r);
  }

  return showDialog<String>(
    context: context,
    builder: (context) =>
        _OpenQuicklyDialog(candidates: candidates, theme: themeManager.current),
  );
}

class _OpenQuicklyDialog extends StatefulWidget {
  const _OpenQuicklyDialog({required this.candidates, required this.theme});

  final List<_Candidate> candidates;
  final dynamic theme;

  @override
  State<_OpenQuicklyDialog> createState() => _OpenQuicklyDialogState();
}

class _OpenQuicklyDialogState extends State<_OpenQuicklyDialog> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  List<_Candidate> _results = const [];
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _results = widget.candidates.take(50).toList();
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onQuery(String q) {
    final scored = <(int, _Candidate)>[];
    for (final c in widget.candidates) {
      final s = _fuzzyScore(q, c.name) ?? _fuzzyScore(q, c.path);
      if (s != null) scored.add((s, c));
    }
    scored.sort((a, b) => a.$1.compareTo(b.$1));
    setState(() {
      _results = [for (final e in scored.take(50)) e.$2];
      _selected = 0;
    });
  }

  void _accept() {
    if (_selected >= 0 && _selected < _results.length) {
      Navigator.of(context).pop(_results[_selected].path);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() =>
          _selected = (_selected + 1).clamp(0, _results.length - 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() => _selected = (_selected - 1).clamp(0, _results.length - 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _accept();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 120),
      child: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Focus(
              onKeyEvent: _onKey,
              child: TextField(
                controller: _query,
                focusNode: _focus,
                autofocus: true,
                onChanged: _onQuery,
                onSubmitted: (_) => _accept(),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Open quickly…',
                  contentPadding: EdgeInsets.all(16),
                  border: InputBorder.none,
                ),
              ),
            ),
            const Divider(height: 1),
            if (_results.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No matching files'),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  itemBuilder: (context, i) {
                    final c = _results[i];
                    final selected = i == _selected;
                    return Container(
                      color: selected
                          ? theme.accent.withValues(alpha: 0.15)
                          : null,
                      child: ListTile(
                        dense: true,
                        title: Text(c.name),
                        subtitle: Text(c.path,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => Navigator.of(context).pop(c.path),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
