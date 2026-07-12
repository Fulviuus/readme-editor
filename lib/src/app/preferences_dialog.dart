/// The Preferences window (app menu > Settings…), organized like the
/// docs: Files, Editor, Image, Markdown, Export, Appearance, General.
/// Values persist through their owning controllers.
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

class _PreferencesDialog extends StatelessWidget {
  const _PreferencesDialog();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    final workspace = context.watch<WorkspaceController>();
    final themeManager = context.watch<ThemeManager>();

    Widget toggle(String title, String subtitle, bool value,
        ValueChanged<bool> onChanged) {
      return SwitchListTile(
        dense: true,
        title: Text(title),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        value: value,
        onChanged: onChanged,
      );
    }

    Widget choice<T>(String title, T value, Map<T, String> options,
        ValueChanged<T> onChanged) {
      return ListTile(
        dense: true,
        title: Text(title),
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
    }

    Widget section(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
          child: Text(title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: Theme.of(context).hintColor,
              )),
        );

    return Dialog(
      child: SizedBox(
        width: 520,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  const Text('Preferences',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  section('FILES'),
                  choice('On launch', s.launchAction, const {
                    'new': 'Open new document',
                    'reopenLast': 'Reopen last file',
                  }, (v) => s.update('launchAction', v, () => s.launchAction = v)),
                  choice('Default extension', s.defaultExtension, const {
                    'md': '.md',
                    'markdown': '.markdown',
                    'txt': '.txt',
                  }, (v) => s.update('defaultExtension', v,
                      () => s.defaultExtension = v)),
                  toggle(
                    'Save when switching files',
                    'Save silently instead of asking when opening another '
                        'file from the sidebar',
                    s.saveOnFileSwitch,
                    (v) => s.update(
                        'saveOnFileSwitch', v, () => s.saveOnFileSwitch = v),
                  ),
                  toggle(
                    'Record recent files',
                    'Track opened files for File > Open Recent',
                    s.recordRecentFiles,
                    (v) => s.update('recordRecentFiles', v,
                        () => s.recordRecentFiles = v),
                  ),
                  toggle(
                    'Autosave',
                    'Write changes back to the file automatically',
                    workspace.autosaveEnabled,
                    (v) => workspace.setAutosave(v),
                  ),
                  section('EDITOR'),
                  toggle(
                    'Check spelling',
                    'Underline misspellings while editing a block',
                    s.spellCheck,
                    (v) => s.setSpellCheck(v),
                  ),
                  toggle(
                    'Auto pair brackets and quotes',
                    'Typing ( [ { " or \' inserts the closing pair',
                    s.autoPairBrackets,
                    (v) => s.update(
                        'autoPairBrackets', v, () => s.autoPairBrackets = v),
                  ),
                  toggle(
                    'Auto pair markdown syntax',
                    'Typing * _ ~ or ` inserts the closing marker',
                    s.autoPairMarkdown,
                    (v) => s.update(
                        'autoPairMarkdown', v, () => s.autoPairMarkdown = v),
                  ),
                  section('IMAGE'),
                  toggle(
                    'Copy images next to the document',
                    'Inserted or pasted images go into an assets folder '
                        'beside the file',
                    s.copyImagesToAssets,
                    (v) => s.update('copyImagesToAssets', v,
                        () => s.copyImagesToAssets = v),
                  ),
                  toggle(
                    'Use relative paths when possible',
                    'Link images relative to the document instead of '
                        'absolute paths',
                    s.relativeImagePaths,
                    (v) => s.update('relativeImagePaths', v,
                        () => s.relativeImagePaths = v),
                  ),
                  toggle(
                    'Add ./ to relative paths',
                    'Prefix relative image links with ./',
                    s.dotSlashImagePaths,
                    (v) => s.update('dotSlashImagePaths', v,
                        () => s.dotSlashImagePaths = v),
                  ),
                  section('MARKDOWN'),
                  choice('Bullet list marker', s.bulletMarker, const {
                    '-': '-',
                    '*': '*',
                    '+': '+',
                  }, (v) => s.update('bulletMarker', v, () => s.bulletMarker = v)),
                  toggle(
                    'Inline math',
                    r'Render $…$ as math (off leaves it as plain text)',
                    s.inlineMath,
                    (v) => s.update('inlineMath', v, () => s.inlineMath = v),
                  ),
                  toggle(
                    'Diagrams',
                    'Render mermaid code fences as diagrams',
                    s.diagrams,
                    (v) => s.update('diagrams', v, () => s.diagrams = v),
                  ),
                  toggle(
                    'Line numbers in code fences',
                    'Show a line-number gutter on rendered code blocks',
                    s.codeLineNumbers,
                    (v) => s.update(
                        'codeLineNumbers', v, () => s.codeLineNumbers = v),
                  ),
                  toggle(
                    'Smart quotes',
                    'Convert straight quotes to curly while typing',
                    s.smartQuotes,
                    (v) => s.update('smartQuotes', v, () => s.smartQuotes = v),
                  ),
                  toggle(
                    'Smart dashes',
                    'Convert -- to an em dash while typing',
                    s.smartDashes,
                    (v) => s.update('smartDashes', v, () => s.smartDashes = v),
                  ),
                  toggle(
                    'Preserve single line break',
                    'Render a lone newline as a line break instead of a space',
                    s.preserveSingleLineBreak,
                    (v) => s.update('preserveSingleLineBreak', v,
                        () => s.preserveSingleLineBreak = v),
                  ),
                  toggle(
                    'Visible <br>',
                    'Show <br> tags as a ↵ glyph in rendered text',
                    s.visibleBr,
                    (v) => s.update('visibleBr', v, () => s.visibleBr = v),
                  ),
                  section('EXPORT'),
                  ListTile(
                    dense: true,
                    title: const Text('Pandoc path'),
                    subtitle: Text(
                        s.pandocPath.isEmpty
                            ? 'Auto-discover (used for Import and '
                                'OpenDocument export)'
                            : s.pandocPath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12)),
                    trailing: TextButton(
                      onPressed: () async {
                        final ctrl =
                            TextEditingController(text: s.pandocPath);
                        final value = await showDialog<String>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Pandoc path'),
                            content: TextField(
                              controller: ctrl,
                              decoration: const InputDecoration(
                                  hintText: 'Leave empty to auto-discover'),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.of(context)
                                    .pop(ctrl.text.trim()),
                                child: const Text('Save'),
                              ),
                            ],
                          ),
                        );
                        if (value != null) {
                          await s.update(
                              'pandocPath', value, () => s.pandocPath = value);
                        }
                        ctrl.dispose();
                      },
                      child: const Text('Change…'),
                    ),
                  ),
                  toggle(
                    'Show exported file',
                    'Reveal the exported file in the file manager afterwards',
                    s.revealAfterExport,
                    (v) => s.update(
                        'revealAfterExport', v, () => s.revealAfterExport = v),
                  ),
                  section('APPEARANCE'),
                  ListTile(
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
                  ),
                  ListTile(
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
                  ),
                  if (themeManager.userThemesDirectory != null)
                    ListTile(
                      dense: true,
                      title: const Text('Custom themes folder'),
                      subtitle: Text(themeManager.userThemesDirectory!,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: TextButton(
                        onPressed: () => launchUrl(
                            Uri.directory(themeManager.userThemesDirectory!)),
                        child: const Text('Open'),
                      ),
                    ),
                  section('GENERAL'),
                  toggle(
                    'Check for updates automatically',
                    'Look for a new version at launch and mention it only '
                        'when one exists',
                    s.checkUpdatesAutomatically,
                    (v) => s.update('checkUpdatesAutomatically', v,
                        () => s.checkUpdatesAutomatically = v),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
