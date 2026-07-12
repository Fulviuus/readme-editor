/// The Preferences window (app menu > Settings…): a left navigation rail
/// (searchable) with one page per section — Files, Editor, Image,
/// Markdown, Export, Appearance, General. Values persist through their
/// owning controllers.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/theme_manager.dart';
import '../workspace/workspace_controller.dart';
import 'settings_controller.dart';

Future<void> showPreferences(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _PreferencesDialog(),
  );
}

class _Entry {
  const _Entry(this.title, this.subtitle, this.build);
  final String title;
  final String subtitle;
  final Widget Function(BuildContext) build;

  bool matches(String q) =>
      title.toLowerCase().contains(q) || subtitle.toLowerCase().contains(q);
}

class _Section {
  const _Section(this.name, this.icon, this.entries);
  final String name;
  final IconData icon;
  final List<_Entry> entries;
}

class _PreferencesDialog extends StatefulWidget {
  const _PreferencesDialog();

  @override
  State<_PreferencesDialog> createState() => _PreferencesDialogState();
}

class _PreferencesDialogState extends State<_PreferencesDialog> {
  var _selected = 0;
  var _query = '';
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // ---- Tile builders ----

  _Entry _toggle(String title, String subtitle, bool value,
      ValueChanged<bool> onChanged) {
    return _Entry(title, subtitle, (context) {
      return SwitchListTile(
        dense: true,
        title: Text(title),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        value: value,
        onChanged: onChanged,
      );
    });
  }

  _Entry _choice<T>(String title, String subtitle, T value,
      Map<T, String> options, ValueChanged<T> onChanged) {
    return _Entry(title, subtitle, (context) {
      return ListTile(
        dense: true,
        title: Text(title),
        subtitle: subtitle.isEmpty
            ? null
            : Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: DropdownButton<T>(
          value: value,
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
          items: [
            for (final e in options.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
        ),
      );
    });
  }

  List<_Section> _sections(BuildContext context) {
    final s = context.watch<SettingsController>();
    final workspace = context.watch<WorkspaceController>();
    final themeManager = context.watch<ThemeManager>();

    return [
      _Section('Files', Icons.description_outlined, [
        _choice('On launch', 'What a new window opens with', s.launchAction, {
          'new': 'Open new document',
          'reopenLast': 'Reopen last file',
        }, (v) => s.update('launchAction', v, () => s.launchAction = v)),
        _choice(
            'Default extension',
            'Used for new documents and Save As',
            s.defaultExtension,
            {'md': '.md', 'markdown': '.markdown', 'txt': '.txt'},
            (v) => s.update(
                'defaultExtension', v, () => s.defaultExtension = v)),
        _toggle(
          'Save when switching files',
          'Save silently instead of asking when opening another file '
              'from the sidebar',
          s.saveOnFileSwitch,
          (v) =>
              s.update('saveOnFileSwitch', v, () => s.saveOnFileSwitch = v),
        ),
        _toggle(
          'Record recent files',
          'Track opened files for File > Open Recent',
          s.recordRecentFiles,
          (v) => s.update(
              'recordRecentFiles', v, () => s.recordRecentFiles = v),
        ),
        _toggle(
          'Autosave',
          'Write changes back to the file automatically',
          workspace.autosaveEnabled,
          (v) => workspace.setAutosave(v),
        ),
      ]),
      _Section('Editor', Icons.edit_outlined, [
        _toggle(
          'Check spelling',
          'Underline misspellings while editing a block',
          s.spellCheck,
          (v) => s.setSpellCheck(v),
        ),
        _toggle(
          'Auto pair brackets and quotes',
          'Typing ( [ { " or \' inserts the closing pair',
          s.autoPairBrackets,
          (v) =>
              s.update('autoPairBrackets', v, () => s.autoPairBrackets = v),
        ),
        _toggle(
          'Auto pair markdown syntax',
          'Typing * _ ~ or ` inserts the closing marker',
          s.autoPairMarkdown,
          (v) =>
              s.update('autoPairMarkdown', v, () => s.autoPairMarkdown = v),
        ),
        _toggle(
          'Smart quotes',
          'Convert straight quotes to curly while typing',
          s.smartQuotes,
          (v) => s.update('smartQuotes', v, () => s.smartQuotes = v),
        ),
        _toggle(
          'Smart dashes',
          'Convert -- to an em dash while typing',
          s.smartDashes,
          (v) => s.update('smartDashes', v, () => s.smartDashes = v),
        ),
      ]),
      _Section('Image', Icons.image_outlined, [
        _toggle(
          'Copy images next to the document',
          'Inserted or pasted images go into an assets folder beside '
              'the file',
          s.copyImagesToAssets,
          (v) => s.update(
              'copyImagesToAssets', v, () => s.copyImagesToAssets = v),
        ),
        _toggle(
          'Use relative paths when possible',
          'Link images relative to the document instead of absolute paths',
          s.relativeImagePaths,
          (v) => s.update(
              'relativeImagePaths', v, () => s.relativeImagePaths = v),
        ),
        _toggle(
          'Add ./ to relative paths',
          'Prefix relative image links with ./',
          s.dotSlashImagePaths,
          (v) => s.update(
              'dotSlashImagePaths', v, () => s.dotSlashImagePaths = v),
        ),
      ]),
      _Section('Markdown', Icons.tag, [
        _choice(
            'Bullet list marker',
            'Used when converting to an unordered list',
            s.bulletMarker,
            {'-': '-', '*': '*', '+': '+'},
            (v) => s.update('bulletMarker', v, () => s.bulletMarker = v)),
        _toggle(
          'Inline math',
          r'Render $…$ as math (off leaves it as plain text)',
          s.inlineMath,
          (v) => s.update('inlineMath', v, () => s.inlineMath = v),
        ),
        _toggle(
          'Diagrams',
          'Render mermaid code fences as diagrams',
          s.diagrams,
          (v) => s.update('diagrams', v, () => s.diagrams = v),
        ),
        _toggle(
          'Line numbers in code fences',
          'Show a line-number gutter on rendered code blocks',
          s.codeLineNumbers,
          (v) =>
              s.update('codeLineNumbers', v, () => s.codeLineNumbers = v),
        ),
        _toggle(
          'Preserve single line break',
          'Render a lone newline as a line break instead of a space',
          s.preserveSingleLineBreak,
          (v) => s.update('preserveSingleLineBreak', v,
              () => s.preserveSingleLineBreak = v),
        ),
        _toggle(
          'Visible <br>',
          'Show <br> tags as a ↵ glyph in rendered text',
          s.visibleBr,
          (v) => s.update('visibleBr', v, () => s.visibleBr = v),
        ),
      ]),
      _Section('Export', Icons.ios_share_outlined, [
        _Entry('Pandoc path',
            'Used for Import and OpenDocument export; empty auto-discovers',
            (context) {
          return ListTile(
            dense: true,
            title: const Text('Pandoc path'),
            subtitle: Text(
                s.pandocPath.isEmpty
                    ? 'Auto-discover (used for Import and OpenDocument '
                        'export)'
                    : s.pandocPath,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12)),
            trailing: TextButton(
              onPressed: () => _editPandocPath(s),
              child: const Text('Change…'),
            ),
          );
        }),
        _toggle(
          'Show exported file',
          'Reveal the exported file in the file manager afterwards',
          s.revealAfterExport,
          (v) => s.update(
              'revealAfterExport', v, () => s.revealAfterExport = v),
        ),
      ]),
      _Section('Appearance', Icons.palette_outlined, [
        _Entry('Theme', 'Active document theme', (context) {
          return ListTile(
            dense: true,
            title: const Text('Theme'),
            trailing: DropdownButton<String>(
              value: themeManager.current.id,
              onChanged: (id) {
                if (id != null) themeManager.setTheme(id);
              },
              items: [
                for (final t in themeManager.themes)
                  DropdownMenuItem(value: t.id, child: Text(t.name)),
              ],
            ),
          );
        }),
        _Entry('Zoom', 'Scale the document text', (context) {
          return ListTile(
            dense: true,
            title: const Text('Zoom'),
            subtitle: Text('${(themeManager.zoom * 100).round()}%'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: themeManager.zoomOut),
                IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: themeManager.zoomIn),
                TextButton(
                    onPressed: themeManager.resetZoom,
                    child: const Text('Reset')),
              ],
            ),
          );
        }),
        if (themeManager.userThemesDirectory != null)
          _Entry('Custom themes folder', 'Drop .json themes here',
              (context) {
            return ListTile(
              dense: true,
              title: const Text('Custom themes folder'),
              subtitle: Text(themeManager.userThemesDirectory!,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: TextButton(
                onPressed: () => launchUrl(
                    Uri.directory(themeManager.userThemesDirectory!)),
                child: const Text('Open'),
              ),
            );
          }),
      ]),
      _Section('General', Icons.settings_outlined, [
        _toggle(
          'Check for updates automatically',
          'Look for a new version at launch and mention it only when one '
              'exists',
          s.checkUpdatesAutomatically,
          (v) => s.update('checkUpdatesAutomatically', v,
              () => s.checkUpdatesAutomatically = v),
        ),
      ]),
    ];
  }

  Future<void> _editPandocPath(SettingsController s) async {
    final ctrl = TextEditingController(text: s.pandocPath);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pandoc path'),
        content: TextField(
          controller: ctrl,
          decoration:
              const InputDecoration(hintText: 'Leave empty to auto-discover'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value != null) {
      await s.update('pandocPath', value, () => s.pandocPath = value);
    }
    ctrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sections = _sections(context);
    final theme = Theme.of(context);
    final q = _query.trim().toLowerCase();

    final Widget content;
    if (q.isNotEmpty) {
      // Search: matching settings from every section, grouped.
      final results = <Widget>[];
      for (final sec in sections) {
        final hits = sec.entries.where((e) => e.matches(q)).toList();
        if (hits.isEmpty) continue;
        results.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
          child: Text(sec.name.toUpperCase(),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: theme.hintColor)),
        ));
        results.addAll(hits.map((e) => e.build(context)));
      }
      content = results.isEmpty
          ? Center(
              child: Text('No matching settings',
                  style: TextStyle(color: theme.hintColor)))
          : ListView(children: results);
    } else {
      final sec = sections[_selected.clamp(0, sections.length - 1)];
      content = ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        children: [for (final e in sec.entries) e.build(context)],
      );
    }

    return Dialog(
      child: SizedBox(
        width: 720,
        height: 480,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- Navigation rail ----
            Container(
              width: 200,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.04),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
                    child: TextField(
                      controller: _search,
                      onChanged: (v) => setState(() => _query = v),
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search…',
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 16),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (var i = 0; i < sections.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 1),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(7),
                              onTap: () => setState(() {
                                _selected = i;
                                _query = '';
                                _search.clear();
                              }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: i == _selected && q.isEmpty
                                      ? theme.colorScheme.onSurface
                                          .withValues(alpha: 0.08)
                                      : null,
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: Row(
                                  children: [
                                    Icon(sections[i].icon,
                                        size: 17,
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.75)),
                                    const SizedBox(width: 10),
                                    Text(sections[i].name,
                                        style:
                                            const TextStyle(fontSize: 13.5)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ---- Content pane ----
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                    child: Row(
                      children: [
                        Text(
                          q.isNotEmpty
                              ? 'Search results'
                              : sections[_selected].name,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: content),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
