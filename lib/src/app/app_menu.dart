/// Menu definitions for the app shell: the macOS [PlatformMenuBar] menus and
/// the Material [MenuBar] used on every other platform. Pure definitions —
/// state and the confirm-if-dirty flows live in HomeShell and arrive through
/// [AppMenuCallbacks].
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../editor/editor_controller.dart';
import '../theme/theme_manager.dart';
import '../workspace/workspace_controller.dart';
import 'platform/window_support.dart';

/// Shell-owned menu actions. File actions already run the confirm-if-dirty
/// flow; editor/theme actions are invoked directly on the controllers.
class AppMenuCallbacks {
  const AppMenuCallbacks({
    required this.about,
    required this.newFile,
    required this.openFile,
    required this.openFolder,
    required this.openRecent,
    required this.save,
    required this.saveAs,
    required this.exportHtml,
    required this.toggleSidebar,
    required this.quit,
    required this.alwaysOnTop,
    required this.toggleAlwaysOnTop,
    required this.insertTable,
  });

  final VoidCallback about;
  final VoidCallback newFile;
  final VoidCallback openFile;
  final VoidCallback openFolder;
  final void Function(String path) openRecent;
  final VoidCallback save;
  final VoidCallback saveAs;
  final VoidCallback exportHtml;
  final VoidCallback toggleSidebar;
  final VoidCallback quit;
  final bool alwaysOnTop;
  final VoidCallback toggleAlwaysOnTop;
  final VoidCallback insertTable;
}

// ---- macOS: PlatformMenuBar ----

/// The native macOS menu bar. Key equivalents are owned by the platform menu
/// (the editor deliberately binds none of them on native macOS).
List<PlatformMenu> buildPlatformMenus({
  required AppMenuCallbacks actions,
  required WorkspaceController workspace,
  required EditorController editor,
  required ThemeManager themeManager,
}) {
  final List<String> recents = workspace.recentFiles;
  return [
    PlatformMenu(
      label: 'readme',
      menus: [
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(label: 'About readme', onSelected: actions.about),
          ],
        ),
        if (PlatformProvidedMenuItem.hasMenu(
            PlatformProvidedMenuItemType.servicesSubmenu))
          const PlatformMenuItemGroup(
            members: [
              PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.servicesSubmenu),
            ],
          ),
        PlatformMenuItemGroup(
          members: [
            if (PlatformProvidedMenuItem.hasMenu(
                PlatformProvidedMenuItemType.hide))
              const PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hide),
            if (PlatformProvidedMenuItem.hasMenu(
                PlatformProvidedMenuItemType.hideOtherApplications))
              const PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hideOtherApplications),
            if (PlatformProvidedMenuItem.hasMenu(
                PlatformProvidedMenuItemType.showAllApplications))
              const PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.showAllApplications),
          ],
        ),
        // Deliberately NOT PlatformProvidedMenuItemType.quit: that
        // terminates immediately, bypassing the unsaved-changes prompt.
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'Quit readme',
              shortcut:
                  const SingleActivator(LogicalKeyboardKey.keyQ, meta: true),
              onSelected: actions.quit,
            ),
          ],
        ),
      ],
    ),
    PlatformMenu(
      label: 'File',
      menus: [
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'New',
              shortcut:
                  const SingleActivator(LogicalKeyboardKey.keyN, meta: true),
              onSelected: actions.newFile,
            ),
            PlatformMenuItem(
              label: 'Open…',
              shortcut:
                  const SingleActivator(LogicalKeyboardKey.keyO, meta: true),
              onSelected: actions.openFile,
            ),
            PlatformMenuItem(
                label: 'Open Folder…', onSelected: actions.openFolder),
            PlatformMenu(
              label: 'Open Recent',
              menus: [
                PlatformMenuItemGroup(
                  members: [
                    if (recents.isEmpty)
                      const PlatformMenuItem(label: 'No Recent Files')
                    else
                      for (final path in recents)
                        PlatformMenuItem(
                          label: p.basename(path),
                          onSelected: () => actions.openRecent(path),
                        ),
                  ],
                ),
              ],
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'Save',
              shortcut:
                  const SingleActivator(LogicalKeyboardKey.keyS, meta: true),
              onSelected: actions.save,
            ),
            PlatformMenuItem(
              label: 'Save As…',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyS,
                  meta: true, shift: true),
              onSelected: actions.saveAs,
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
                label: 'Export HTML…', onSelected: actions.exportHtml),
          ],
        ),
      ],
    ),
    PlatformMenu(
      label: 'Edit',
      menus: [
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'Undo',
              shortcut:
                  const SingleActivator(LogicalKeyboardKey.keyZ, meta: true),
              onSelected: editor.undo,
            ),
            PlatformMenuItem(
              label: 'Redo',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyZ,
                  meta: true, shift: true),
              onSelected: editor.redo,
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'Bold',
              shortcut:
                  const SingleActivator(LogicalKeyboardKey.keyB, meta: true),
              onSelected: editor.toggleBold,
            ),
            PlatformMenuItem(
              label: 'Italic',
              shortcut:
                  const SingleActivator(LogicalKeyboardKey.keyI, meta: true),
              onSelected: editor.toggleItalic,
            ),
            PlatformMenuItem(
              label: 'Code',
              shortcut:
                  const SingleActivator(LogicalKeyboardKey.keyE, meta: true),
              onSelected: editor.toggleCode,
            ),
            PlatformMenuItem(
              label: 'Strikethrough',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyD,
                  meta: true, shift: true),
              onSelected: editor.toggleStrikethrough,
            ),
            PlatformMenuItem(
              label: 'Link',
              shortcut:
                  const SingleActivator(LogicalKeyboardKey.keyK, meta: true),
              onSelected: editor.insertLink,
            ),
            PlatformMenuItem(
              label: 'Open Link',
              onSelected: editor.openLinkAtCaret,
            ),
            PlatformMenuItem(
              label: 'Copy Link Address',
              onSelected: editor.copyLinkAtCaret,
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'Move Row Up',
              shortcut: const SingleActivator(LogicalKeyboardKey.arrowUp,
                  meta: true, control: true),
              onSelected: () => editor.moveRow(up: true),
            ),
            PlatformMenuItem(
              label: 'Move Row Down',
              shortcut: const SingleActivator(LogicalKeyboardKey.arrowDown,
                  meta: true, control: true),
              onSelected: () => editor.moveRow(up: false),
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'Find…',
              shortcut:
                  const SingleActivator(LogicalKeyboardKey.keyF, meta: true),
              onSelected: () => editor.findVisible.value = true,
            ),
          ],
        ),
      ],
    ),
    PlatformMenu(
      label: 'Paragraph',
      menus: [
        PlatformMenuItemGroup(
          members: [
            for (var n = 1; n <= 6; n++)
              PlatformMenuItem(
                label: 'Heading $n',
                shortcut:
                    SingleActivator(LogicalKeyboardKey(0x30 + n), meta: true),
                onSelected: () => editor.setHeadingLevel(n),
              ),
            PlatformMenuItem(
              label: 'Paragraph',
              shortcut:
                  const SingleActivator(LogicalKeyboardKey.digit0, meta: true),
              onSelected: () => editor.setHeadingLevel(0),
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'Increase Heading Level',
              shortcut:
                  const SingleActivator(LogicalKeyboardKey.equal, meta: true),
              onSelected: editor.increaseHeadingLevel,
            ),
            PlatformMenuItem(
              label: 'Decrease Heading Level',
              shortcut:
                  const SingleActivator(LogicalKeyboardKey.minus, meta: true),
              onSelected: editor.decreaseHeadingLevel,
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'Insert Table…',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyT,
                  meta: true, alt: true),
              onSelected: actions.insertTable,
            ),
            PlatformMenuItem(
              label: 'Code Fences',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyC,
                  meta: true, alt: true),
              onSelected: editor.convertToCodeFence,
            ),
            PlatformMenuItem(
              label: 'Math Block',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyB,
                  meta: true, alt: true),
              onSelected: editor.convertToMathBlock,
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'Quote',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyQ,
                  meta: true, alt: true),
              onSelected: editor.convertToQuote,
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'Ordered List',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyO,
                  meta: true, alt: true),
              onSelected: editor.convertToOrderedList,
            ),
            PlatformMenuItem(
              label: 'Unordered List',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyU,
                  meta: true, alt: true),
              onSelected: editor.convertToUnorderedList,
            ),
            PlatformMenuItem(
              label: 'Task List',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyX,
                  meta: true, alt: true),
              onSelected: editor.convertToTaskList,
            ),
            PlatformMenu(
              label: 'Task Status',
              menus: [
                PlatformMenuItemGroup(
                  members: [
                    PlatformMenuItem(
                      label: 'Toggle Task Status',
                      onSelected: () => editor.setTaskStatusAtCaret(),
                    ),
                    PlatformMenuItem(
                      label: 'Mark as Complete',
                      onSelected: () =>
                          editor.setTaskStatusAtCaret(checked: true),
                    ),
                    PlatformMenuItem(
                      label: 'Mark as Incomplete',
                      onSelected: () =>
                          editor.setTaskStatusAtCaret(checked: false),
                    ),
                  ],
                ),
              ],
            ),
            PlatformMenu(
              label: 'List Indentation',
              menus: [
                PlatformMenuItemGroup(
                  members: [
                    PlatformMenuItem(
                      label: 'Indent',
                      onSelected: editor.indentListItem,
                    ),
                    PlatformMenuItem(
                      label: 'Outdent',
                      onSelected: editor.outdentListItem,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'Insert Paragraph Before',
              onSelected: editor.insertParagraphBefore,
            ),
            PlatformMenuItem(
              label: 'Insert Paragraph After',
              shortcut:
                  const SingleActivator(LogicalKeyboardKey.enter, meta: true),
              onSelected: editor.insertParagraphAfter,
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'Horizontal Line',
              onSelected: editor.insertHorizontalRule,
            ),
            PlatformMenuItem(
              label: 'YAML Front Matter',
              onSelected: editor.insertFrontMatter,
            ),
          ],
        ),
      ],
    ),
    PlatformMenu(
      label: 'View',
      menus: [
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'Toggle Sidebar',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyL,
                  meta: true, shift: true),
              onSelected: actions.toggleSidebar,
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'Source Mode',
              shortcut:
                  const SingleActivator(LogicalKeyboardKey.slash, meta: true),
              onSelected: editor.toggleSourceMode,
            ),
            PlatformMenuItem(
              label: 'Focus Mode',
              shortcut: const SingleActivator(LogicalKeyboardKey.f8),
              onSelected: editor.toggleFocusMode,
            ),
          ],
        ),
        PlatformMenu(
          label: 'Themes',
          menus: [
            PlatformMenuItemGroup(
              members: [
                // Radio-style: checkmark prefix on the active theme
                // (PlatformMenuItem has no native checked state).
                for (final theme in themeManager.themes)
                  PlatformMenuItem(
                    label: theme.id == themeManager.current.id
                        ? '✓ ${theme.name}'
                        : '   ${theme.name}',
                    onSelected: () => themeManager.setTheme(theme.id),
                  ),
              ],
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: actions.alwaysOnTop ? '✓ Always on Top' : 'Always on Top',
              onSelected: actions.toggleAlwaysOnTop,
            ),
          ],
        ),
      ],
    ),
    PlatformMenu(
      label: 'Window',
      menus: [
        PlatformMenuItemGroup(
          members: [
            if (PlatformProvidedMenuItem.hasMenu(
                PlatformProvidedMenuItemType.minimizeWindow))
              const PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.minimizeWindow),
            if (PlatformProvidedMenuItem.hasMenu(
                PlatformProvidedMenuItemType.zoomWindow))
              const PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.zoomWindow),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            if (PlatformProvidedMenuItem.hasMenu(
                PlatformProvidedMenuItemType.toggleFullScreen))
              const PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.toggleFullScreen),
            if (PlatformProvidedMenuItem.hasMenu(
                PlatformProvidedMenuItemType.arrangeWindowsInFront))
              const PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.arrangeWindowsInFront),
          ],
        ),
      ],
    ),
  ];
}

// ---- Everything else: Material MenuBar ----

/// Material menu bar for Windows/Linux/web. Displays the same actions; the
/// shell-level shortcuts (Ctrl+N/O/S…) are bound by HomeShell, and the
/// formatting/undo shortcuts by the editor itself.
class AppMenuBar extends StatelessWidget {
  const AppMenuBar({
    super.key,
    required this.actions,
    required this.workspace,
    required this.editor,
    required this.themeManager,
  });

  final AppMenuCallbacks actions;
  final WorkspaceController workspace;
  final EditorController editor;
  final ThemeManager themeManager;

  @override
  Widget build(BuildContext context) {
    final theme = themeManager.current;
    // Match the editor's convention: meta on macOS-web, control elsewhere.
    final meta = defaultTargetPlatform == TargetPlatform.macOS;
    SingleActivator cmd(LogicalKeyboardKey key, {bool shift = false}) =>
        SingleActivator(key, meta: meta, control: !meta, shift: shift);
    final List<String> recents = workspace.recentFiles;

    return MenuBar(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(theme.sidebarBackground),
        elevation: const WidgetStatePropertyAll(0),
      ),
      children: [
        SubmenuButton(
          menuChildren: [
            MenuItemButton(
              onPressed: actions.newFile,
              shortcut: cmd(LogicalKeyboardKey.keyN),
              child: const Text('New'),
            ),
            MenuItemButton(
              onPressed: actions.openFile,
              shortcut: cmd(LogicalKeyboardKey.keyO),
              child: const Text('Open…'),
            ),
            MenuItemButton(
              onPressed: actions.openFolder,
              child: const Text('Open Folder…'),
            ),
            SubmenuButton(
              menuChildren: [
                if (recents.isEmpty)
                  const MenuItemButton(child: Text('No Recent Files'))
                else
                  for (final path in recents)
                    MenuItemButton(
                      onPressed: () => actions.openRecent(path),
                      child: Text(p.basename(path)),
                    ),
              ],
              child: const Text('Open Recent'),
            ),
            const Divider(height: 8),
            MenuItemButton(
              onPressed: actions.save,
              shortcut: cmd(LogicalKeyboardKey.keyS),
              child: const Text('Save'),
            ),
            MenuItemButton(
              onPressed: actions.saveAs,
              shortcut: cmd(LogicalKeyboardKey.keyS, shift: true),
              child: const Text('Save As…'),
            ),
            const Divider(height: 8),
            MenuItemButton(
              onPressed: actions.exportHtml,
              child: const Text('Export HTML…'),
            ),
          ],
          child: const MenuAcceleratorLabel('&File'),
        ),
        SubmenuButton(
          menuChildren: [
            MenuItemButton(
              onPressed: editor.undo,
              shortcut: cmd(LogicalKeyboardKey.keyZ),
              child: const Text('Undo'),
            ),
            MenuItemButton(
              onPressed: editor.redo,
              shortcut: cmd(LogicalKeyboardKey.keyZ, shift: true),
              child: const Text('Redo'),
            ),
            const Divider(height: 8),
            MenuItemButton(
              onPressed: editor.toggleBold,
              shortcut: cmd(LogicalKeyboardKey.keyB),
              child: const Text('Bold'),
            ),
            MenuItemButton(
              onPressed: editor.toggleItalic,
              shortcut: cmd(LogicalKeyboardKey.keyI),
              child: const Text('Italic'),
            ),
            MenuItemButton(
              onPressed: editor.toggleCode,
              shortcut: cmd(LogicalKeyboardKey.keyE),
              child: const Text('Code'),
            ),
            MenuItemButton(
              onPressed: editor.toggleStrikethrough,
              shortcut: cmd(LogicalKeyboardKey.keyD, shift: true),
              child: const Text('Strikethrough'),
            ),
            MenuItemButton(
              onPressed: editor.insertLink,
              shortcut: cmd(LogicalKeyboardKey.keyK),
              child: const Text('Link'),
            ),
            MenuItemButton(
              onPressed: editor.openLinkAtCaret,
              child: const Text('Open Link'),
            ),
            MenuItemButton(
              onPressed: editor.copyLinkAtCaret,
              child: const Text('Copy Link Address'),
            ),
            const Divider(height: 8),
            MenuItemButton(
              onPressed: () => editor.moveRow(up: true),
              child: const Text('Move Row Up'),
            ),
            MenuItemButton(
              onPressed: () => editor.moveRow(up: false),
              child: const Text('Move Row Down'),
            ),
            const Divider(height: 8),
            MenuItemButton(
              onPressed: () => editor.findVisible.value = true,
              shortcut: cmd(LogicalKeyboardKey.keyF),
              child: const Text('Find…'),
            ),
          ],
          child: const MenuAcceleratorLabel('&Edit'),
        ),
        SubmenuButton(
          menuChildren: [
            for (var n = 1; n <= 6; n++)
              MenuItemButton(
                onPressed: () => editor.setHeadingLevel(n),
                shortcut: SingleActivator(LogicalKeyboardKey(0x30 + n),
                    meta: meta, control: !meta),
                child: Text('Heading $n'),
              ),
            MenuItemButton(
              onPressed: () => editor.setHeadingLevel(0),
              shortcut: cmd(LogicalKeyboardKey.digit0),
              child: const Text('Paragraph'),
            ),
            const Divider(height: 8),
            MenuItemButton(
              onPressed: editor.increaseHeadingLevel,
              shortcut: cmd(LogicalKeyboardKey.equal),
              child: const Text('Increase Heading Level'),
            ),
            MenuItemButton(
              onPressed: editor.decreaseHeadingLevel,
              shortcut: cmd(LogicalKeyboardKey.minus),
              child: const Text('Decrease Heading Level'),
            ),
            const Divider(height: 8),
            MenuItemButton(
              onPressed: actions.insertTable,
              child: const Text('Insert Table…'),
            ),
            MenuItemButton(
              onPressed: editor.convertToCodeFence,
              child: const Text('Code Fences'),
            ),
            MenuItemButton(
              onPressed: editor.convertToMathBlock,
              child: const Text('Math Block'),
            ),
            MenuItemButton(
              onPressed: editor.convertToQuote,
              child: const Text('Quote'),
            ),
            const Divider(height: 8),
            MenuItemButton(
              onPressed: editor.convertToOrderedList,
              child: const Text('Ordered List'),
            ),
            MenuItemButton(
              onPressed: editor.convertToUnorderedList,
              child: const Text('Unordered List'),
            ),
            MenuItemButton(
              onPressed: editor.convertToTaskList,
              child: const Text('Task List'),
            ),
            SubmenuButton(
              menuChildren: [
                MenuItemButton(
                  onPressed: () => editor.setTaskStatusAtCaret(),
                  child: const Text('Toggle Task Status'),
                ),
                MenuItemButton(
                  onPressed: () => editor.setTaskStatusAtCaret(checked: true),
                  child: const Text('Mark as Complete'),
                ),
                MenuItemButton(
                  onPressed: () => editor.setTaskStatusAtCaret(checked: false),
                  child: const Text('Mark as Incomplete'),
                ),
              ],
              child: const Text('Task Status'),
            ),
            SubmenuButton(
              menuChildren: [
                MenuItemButton(
                  onPressed: editor.indentListItem,
                  child: const Text('Indent'),
                ),
                MenuItemButton(
                  onPressed: editor.outdentListItem,
                  child: const Text('Outdent'),
                ),
              ],
              child: const Text('List Indentation'),
            ),
            const Divider(height: 8),
            MenuItemButton(
              onPressed: editor.insertParagraphBefore,
              child: const Text('Insert Paragraph Before'),
            ),
            MenuItemButton(
              onPressed: editor.insertParagraphAfter,
              child: const Text('Insert Paragraph After'),
            ),
            const Divider(height: 8),
            MenuItemButton(
              onPressed: editor.insertHorizontalRule,
              child: const Text('Horizontal Line'),
            ),
            MenuItemButton(
              onPressed: editor.insertFrontMatter,
              child: const Text('YAML Front Matter'),
            ),
          ],
          child: const MenuAcceleratorLabel('&Paragraph'),
        ),
        SubmenuButton(
          menuChildren: [
            MenuItemButton(
              onPressed: actions.toggleSidebar,
              shortcut: cmd(LogicalKeyboardKey.keyL, shift: true),
              child: const Text('Toggle Sidebar'),
            ),
            const Divider(height: 8),
            MenuItemButton(
              onPressed: editor.toggleSourceMode,
              shortcut: cmd(LogicalKeyboardKey.slash),
              child: const Text('Source Mode'),
            ),
            MenuItemButton(
              onPressed: editor.toggleFocusMode,
              shortcut: const SingleActivator(LogicalKeyboardKey.f8),
              child: const Text('Focus Mode'),
            ),
            const Divider(height: 8),
            SubmenuButton(
              menuChildren: [
                for (final t in themeManager.themes)
                  MenuItemButton(
                    leadingIcon: t.id == themeManager.current.id
                        ? const Icon(Icons.check, size: 16)
                        : const SizedBox(width: 16),
                    onPressed: () => themeManager.setTheme(t.id),
                    child: Text(t.name),
                  ),
              ],
              child: const Text('Themes'),
            ),
            const Divider(height: 8),
            MenuItemButton(
              leadingIcon: actions.alwaysOnTop
                  ? const Icon(Icons.check, size: 16)
                  : const SizedBox(width: 16),
              onPressed: actions.toggleAlwaysOnTop,
              child: const Text('Always on Top'),
            ),
          ],
          child: const MenuAcceleratorLabel('&View'),
        ),
        SubmenuButton(
          menuChildren: [
            MenuItemButton(
              onPressed: minimizeWindow,
              child: const Text('Minimize'),
            ),
            MenuItemButton(
              onPressed: zoomWindow,
              child: const Text('Zoom'),
            ),
            const Divider(height: 8),
            MenuItemButton(
              onPressed: toggleFullScreenWindow,
              shortcut: const SingleActivator(LogicalKeyboardKey.f11),
              child: const Text('Full Screen'),
            ),
          ],
          child: const MenuAcceleratorLabel('&Window'),
        ),
      ],
    );
  }
}
