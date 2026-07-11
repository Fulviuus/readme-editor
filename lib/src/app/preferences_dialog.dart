/// The Preferences window (app menu > Settings…): general, editor and
/// appearance settings. Values persist through their owning controllers.
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
    final settings = context.watch<SettingsController>();
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

    Widget section(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
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
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              section('GENERAL'),
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
                settings.spellCheck,
                (v) => settings.setSpellCheck(v),
              ),
              toggle(
                'Smart quotes',
                'Convert straight quotes to curly while typing',
                settings.smartQuotes,
                (v) => settings.setSmartQuotes(v),
              ),
              toggle(
                'Smart dashes',
                'Convert -- to an em dash while typing',
                settings.smartDashes,
                (v) => settings.setSmartDashes(v),
              ),
              toggle(
                'Preserve single line break',
                'Render a lone newline as a line break instead of a space',
                settings.preserveSingleLineBreak,
                (v) => settings.setPreserveSingleLineBreak(v),
              ),
              toggle(
                'Visible <br>',
                'Show <br> tags as a ↵ glyph in rendered text',
                settings.visibleBr,
                (v) => settings.setVisibleBr(v),
              ),
              toggle(
                'Copy images next to the document',
                'Inserted or pasted images go into an assets folder beside '
                    'the file, linked relatively',
                settings.copyImagesToAssets,
                (v) => settings.setCopyImagesToAssets(v),
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
                subtitle:
                    Text('${(themeManager.zoom * 100).round()}%'),
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
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
