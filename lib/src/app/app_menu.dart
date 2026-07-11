/// Menu definitions for the app shell: the macOS [PlatformMenuBar] menus and
/// the Material [MenuBar] used on every other platform. Pure definitions —
/// state and the confirm-if-dirty flows live in HomeShell and arrive through
/// [AppMenuCallbacks].
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../document/block.dart';
import '../editor/editor_controller.dart';
import '../theme/theme_manager.dart';
import '../workspace/workspace_controller.dart';
import 'platform/window_support.dart';
import 'sidebar/sidebar_pane.dart';

/// Shell-owned menu actions. File actions already run the confirm-if-dirty
/// flow; editor/theme actions are invoked directly on the controllers.
class AppMenuCallbacks {
  const AppMenuCallbacks({
    required this.about,
    required this.newFile,
    required this.newTab,
    required this.closeTab,
    required this.nextTab,
    required this.previousTab,
    required this.revertTo,
    required this.checkForUpdates,
    required this.openFile,
    required this.openFolder,
    required this.openRecent,
    required this.save,
    required this.saveAs,
    required this.paste,
    required this.importFile,
    required this.exportPandoc,
    required this.exportHtml,
    required this.exportPdf,
    required this.exportImage,
    required this.print,
    required this.share,
    required this.toggleSidebar,
    required this.quit,
    required this.alwaysOnTop,
    required this.toggleAlwaysOnTop,
    required this.insertTable,
    required this.insertImage,
    required this.insertLocalImages,
    required this.activeSidebarPane,
    required this.selectSidebarPane,
    required this.hasFilePath,
    required this.openQuickly,
    required this.revealFile,
    required this.duplicateFile,
    required this.renameFile,
    required this.deleteFile,
    required this.autosave,
    required this.toggleAutosave,
    required this.openMarkdownReference,
    required this.openQuickStart,
    required this.preferences,
  });

  final VoidCallback about;
  final VoidCallback newFile;
  final VoidCallback newTab;

  /// Closes the active tab; with a single tab this closes the window.
  final VoidCallback closeTab;
  final VoidCallback nextTab;
  final VoidCallback previousTab;

  /// File > Revert To…: restore a recorded save snapshot.
  final VoidCallback revertTo;
  final VoidCallback checkForUpdates;
  final VoidCallback openFile;
  final VoidCallback openFolder;
  final void Function(String path) openRecent;
  final VoidCallback save;
  final VoidCallback saveAs;

  /// Paste with clipboard-image awareness (falls back to the text intent).
  final VoidCallback paste;
  final VoidCallback importFile;

  /// Export through pandoc; the argument is the target file extension.
  final void Function(String extension) exportPandoc;
  final VoidCallback exportHtml;
  final VoidCallback exportPdf;
  final VoidCallback exportImage;
  final VoidCallback print;
  final VoidCallback share;
  final VoidCallback toggleSidebar;
  final VoidCallback quit;
  final bool alwaysOnTop;
  final VoidCallback toggleAlwaysOnTop;
  final VoidCallback insertTable;
  final VoidCallback insertImage;
  final VoidCallback insertLocalImages;
  final SidebarPane activeSidebarPane;
  final void Function(SidebarPane pane) selectSidebarPane;
  final bool hasFilePath;
  final VoidCallback openQuickly;
  final VoidCallback revealFile;
  final VoidCallback duplicateFile;
  final VoidCallback renameFile;
  final VoidCallback deleteFile;
  final bool autosave;
  final VoidCallback toggleAutosave;
  final VoidCallback openMarkdownReference;
  final VoidCallback openQuickStart;
  final VoidCallback preferences;
}

/// Routes a text-editing intent to the currently focused editable field.
/// Public so the shell's clipboard-aware Paste can fall back to it.
void dispatchTextIntent(Intent intent) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context != null) Actions.maybeInvoke(context, intent);
}

void _dispatchTextIntent(Intent intent) => dispatchTextIntent(intent);

/// PlatformMenuItem has no native checked state; a checkmark prefix (space-
/// aligned when off) is the established stand-in across these menus.
String _checked(String label, bool on) => on ? '✓ $label' : '   $label';

/// Material-menu counterpart: a leading check icon (aligned when off).
Widget _checkIcon(bool on) =>
    on ? const Icon(Icons.check, size: 16) : const SizedBox(width: 16);

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
            PlatformMenuItem(
                label: 'Check for Updates…',
                onSelected: actions.checkForUpdates),
            PlatformMenuItem(
              label: 'Settings…',
              shortcut:
                  const SingleActivator(LogicalKeyboardKey.comma, meta: true),
              onSelected: actions.preferences,
            ),
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
              label: 'New Tab',
              shortcut:
                  const SingleActivator(LogicalKeyboardKey.keyT, meta: true),
              onSelected: actions.newTab,
            ),
            PlatformMenuItem(
              label: 'Close Tab',
              shortcut:
                  const SingleActivator(LogicalKeyboardKey.keyW, meta: true),
              onSelected: actions.closeTab,
            ),
            PlatformMenuItem(
              label: 'Open…',
              shortcut:
                  const SingleActivator(LogicalKeyboardKey.keyO, meta: true),
              onSelected: actions.openFile,
            ),
            PlatformMenuItem(
                label: 'Open Folder…', onSelected: actions.openFolder),
            PlatformMenuItem(
              label: 'Open Quickly…',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyO,
                  meta: true, shift: true),
              onSelected: actions.openQuickly,
            ),
            PlatformMenu(
              label: 'Open Recent',
              menus: [
                if (workspace.lastClosedFile != null)
                  PlatformMenuItemGroup(
                    members: [
                      PlatformMenuItem(
                        label: 'Reopen Closed File',
                        shortcut: const SingleActivator(LogicalKeyboardKey.keyT,
                            meta: true, shift: true),
                        onSelected: () =>
                            actions.openRecent(workspace.lastClosedFile!),
                      ),
                    ],
                  ),
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
                if (recents.isNotEmpty)
                  PlatformMenuItemGroup(
                    members: [
                      PlatformMenuItem(
                        label: 'Clear Items',
                        onSelected: () => workspace.clearRecentFiles(),
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
                label: 'Import…', onSelected: actions.importFile),
          ],
        ),
        if (actions.hasFilePath)
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                  label: 'Reveal in Finder', onSelected: actions.revealFile),
              PlatformMenuItem(
                  label: 'Revert To…', onSelected: actions.revertTo),
              PlatformMenuItem(
                  label: 'Duplicate', onSelected: actions.duplicateFile),
              PlatformMenuItem(
                  label: 'Rename…', onSelected: actions.renameFile),
              PlatformMenuItem(
                  label: 'Move to Trash…', onSelected: actions.deleteFile),
            ],
          ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: actions.autosave ? '✓ Autosave' : 'Autosave',
              onSelected: actions.toggleAutosave,
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(label: 'Share…', onSelected: actions.share),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenu(
              label: 'Export',
              menus: [
                PlatformMenuItemGroup(members: [
                  PlatformMenuItem(
                      label: 'PDF…', onSelected: actions.exportPdf),
                  PlatformMenuItem(
                      label: 'HTML…', onSelected: actions.exportHtml),
                  PlatformMenuItem(
                      label: 'Image…', onSelected: actions.exportImage),
                ]),
                PlatformMenuItemGroup(members: [
                  PlatformMenuItem(
                      label: 'Word (.docx)…',
                      onSelected: () => actions.exportPandoc('docx')),
                  PlatformMenuItem(
                      label: 'OpenDocument (.odt)…',
                      onSelected: () => actions.exportPandoc('odt')),
                  PlatformMenuItem(
                      label: 'Epub (.epub)…',
                      onSelected: () => actions.exportPandoc('epub')),
                  PlatformMenuItem(
                      label: 'LaTeX (.tex)…',
                      onSelected: () => actions.exportPandoc('tex')),
                  PlatformMenuItem(
                      label: 'RTF (.rtf)…',
                      onSelected: () => actions.exportPandoc('rtf')),
                ]),
              ],
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'Print…',
              shortcut:
                  const SingleActivator(LogicalKeyboardKey.keyP, meta: true),
              onSelected: actions.print,
            ),
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
        // Clipboard items dispatch text-editing intents to whatever field
        // has focus (editor block, find bar, source mode) — the menu owns
        // the key equivalents on macOS, so routing must be focus-based.
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'Cut',
              shortcut:
                  const SingleActivator(LogicalKeyboardKey.keyX, meta: true),
              onSelected: () => _dispatchTextIntent(
                  CopySelectionTextIntent.cut(SelectionChangedCause.keyboard)),
            ),
            PlatformMenuItem(
              label: 'Copy',
              shortcut:
                  const SingleActivator(LogicalKeyboardKey.keyC, meta: true),
              onSelected: () =>
                  _dispatchTextIntent(CopySelectionTextIntent.copy),
            ),
            PlatformMenuItem(
              label: 'Paste',
              shortcut:
                  const SingleActivator(LogicalKeyboardKey.keyV, meta: true),
              onSelected: actions.paste,
            ),
            PlatformMenuItem(
              label: 'Select All',
              shortcut:
                  const SingleActivator(LogicalKeyboardKey.keyA, meta: true),
              onSelected: () => _dispatchTextIntent(
                  const SelectAllTextIntent(SelectionChangedCause.keyboard)),
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'Look Up',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyD,
                  meta: true, control: true),
              onSelected: editor.lookUpSelection,
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
                label: 'Copy as Markdown',
                shortcut: const SingleActivator(LogicalKeyboardKey.keyC,
                    meta: true, shift: true),
                onSelected: editor.copyAsMarkdown),
            PlatformMenuItem(
                label: 'Copy as Plain Text', onSelected: editor.copyAsPlainText),
            PlatformMenuItem(
                label: 'Copy as HTML Code', onSelected: editor.copyAsHtml),
            PlatformMenuItem(
                label: 'Paste as Plain Text',
                shortcut: const SingleActivator(LogicalKeyboardKey.keyV,
                    meta: true, shift: true),
                onSelected: () => editor.pasteAsPlainText()),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenu(
              label: 'Selection',
              menus: [
                PlatformMenuItemGroup(members: [
                  PlatformMenuItem(
                      label: 'Select Word', onSelected: editor.selectWord),
                  PlatformMenuItem(
                      label: 'Select Line', onSelected: editor.selectLine),
                  PlatformMenuItem(
                      label: 'Select Paragraph / Block',
                      onSelected: editor.selectBlock),
                  PlatformMenuItem(
                      label: 'Select Styled Scope',
                      onSelected: editor.selectStyledScope),
                ]),
                PlatformMenuItemGroup(members: [
                  PlatformMenuItem(
                      label: 'Jump to Top', onSelected: editor.jumpToTop),
                  PlatformMenuItem(
                      label: 'Jump to Selection',
                      onSelected: editor.jumpToSelection),
                  PlatformMenuItem(
                      label: 'Jump to Bottom', onSelected: editor.jumpToBottom),
                ]),
                PlatformMenuItemGroup(members: [
                  PlatformMenuItem(
                      label: 'Jump to Line Start',
                      onSelected: editor.jumpToLineStart),
                  PlatformMenuItem(
                      label: 'Jump to Line End',
                      onSelected: editor.jumpToLineEnd),
                ]),
              ],
            ),
            PlatformMenu(
              label: 'Delete Range',
              menus: [
                PlatformMenuItemGroup(members: [
                  PlatformMenuItem(
                      label: 'Delete Paragraph / Block',
                      onSelected: editor.deleteBlock),
                  PlatformMenuItem(
                      label: 'Delete Line', onSelected: editor.deleteLine),
                  PlatformMenuItem(
                      label: 'Delete Styled Scope',
                      onSelected: editor.deleteStyledScope),
                  PlatformMenuItem(
                      label: 'Delete Word', onSelected: editor.deleteWord),
                ]),
              ],
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
              label: 'Underline',
              shortcut:
                  const SingleActivator(LogicalKeyboardKey.keyU, meta: true),
              onSelected: editor.toggleUnderline,
            ),
            PlatformMenuItem(
              label: 'Comment',
              shortcut: const SingleActivator(LogicalKeyboardKey.slash,
                  meta: true, shift: true),
              onSelected: editor.toggleComment,
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
            PlatformMenu(
              label: 'Image',
              menus: [
                PlatformMenuItemGroup(members: [
                  PlatformMenuItem(
                      label: 'Insert Image…',
                      onSelected: actions.insertImage),
                  PlatformMenuItem(
                      label: 'Insert Local Images…',
                      onSelected: actions.insertLocalImages),
                ]),
              ],
            ),
            PlatformMenuItem(
              label: 'Clear Format',
              shortcut: const SingleActivator(LogicalKeyboardKey.backslash,
                  meta: true),
              onSelected: editor.clearFormat,
            ),
          ],
        ),
        PlatformMenu(
          label: 'Line Endings',
          menus: [
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: editor.docCtrl.doc.lineEnding == '\r\n'
                      ? '✓ Windows Line Endings (CRLF)'
                      : '   Windows Line Endings (CRLF)',
                  onSelected: () => editor.docCtrl.setLineEnding('\r\n'),
                ),
                PlatformMenuItem(
                  label: editor.docCtrl.doc.lineEnding == '\n'
                      ? '✓ Unix Line Endings (LF)'
                      : '   Unix Line Endings (LF)',
                  onSelected: () => editor.docCtrl.setLineEnding('\n'),
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: editor.docCtrl.doc.hadFinalNewline
                      ? '✓ Insert Final New Line On Save'
                      : '   Insert Final New Line On Save',
                  onSelected: () => editor.docCtrl
                      .setFinalNewline(!editor.docCtrl.doc.hadFinalNewline),
                ),
              ],
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
                label: _checked(
                    'Heading $n', editor.focusedHeadingLevel == n),
                shortcut:
                    SingleActivator(LogicalKeyboardKey(0x30 + n), meta: true),
                onSelected: () => editor.setHeadingLevel(n),
              ),
            PlatformMenuItem(
              label: _checked(
                  'Paragraph', editor.focusedKind == BlockKind.paragraph),
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
            PlatformMenu(
              label: 'Table',
              menus: [
                PlatformMenuItemGroup(
                  members: [
                    PlatformMenuItem(
                      label: 'Insert Table…',
                      shortcut: const SingleActivator(LogicalKeyboardKey.keyT,
                          meta: true, alt: true),
                      onSelected: actions.insertTable,
                    ),
                  ],
                ),
                PlatformMenuItemGroup(
                  members: [
                    PlatformMenuItem(
                        label: 'Add Row Above',
                        onSelected: editor.addTableRowAbove),
                    PlatformMenuItem(
                        label: 'Add Row Below',
                        onSelected: editor.addTableRowBelow),
                    PlatformMenuItem(
                        label: 'Add Column Before',
                        onSelected: editor.addTableColumnBefore),
                    PlatformMenuItem(
                        label: 'Add Column After',
                        onSelected: editor.addTableColumnAfter),
                  ],
                ),
                PlatformMenuItemGroup(
                  members: [
                    PlatformMenuItem(
                        label: 'Move Column Left',
                        onSelected: editor.moveTableColumnLeft),
                    PlatformMenuItem(
                        label: 'Move Column Right',
                        onSelected: editor.moveTableColumnRight),
                  ],
                ),
                PlatformMenuItemGroup(
                  members: [
                    PlatformMenuItem(
                        label: 'Delete Row',
                        onSelected: editor.deleteTableRow),
                    PlatformMenuItem(
                        label: 'Delete Column',
                        onSelected: editor.deleteTableColumn),
                  ],
                ),
                PlatformMenuItemGroup(
                  members: [
                    PlatformMenuItem(
                        label: 'Copy Table', onSelected: editor.copyTable),
                    PlatformMenuItem(
                        label: 'Delete Table',
                        onSelected: editor.deleteTable),
                  ],
                ),
              ],
            ),
            PlatformMenuItem(
              label: _checked(
                  'Code Fences',
                  editor.focusedKind == BlockKind.fencedCode ||
                      editor.focusedKind == BlockKind.indentedCode),
              shortcut: const SingleActivator(LogicalKeyboardKey.keyC,
                  meta: true, alt: true),
              onSelected: editor.convertToCodeFence,
            ),
            PlatformMenuItem(
              label: _checked(
                  'Math Block', editor.focusedKind == BlockKind.mathBlock),
              shortcut: const SingleActivator(LogicalKeyboardKey.keyB,
                  meta: true, alt: true),
              onSelected: editor.convertToMathBlock,
            ),
            PlatformMenu(
              label: 'Code Tools',
              menus: [
                PlatformMenuItemGroup(members: [
                  PlatformMenuItem(
                      label: 'Copy Code Content',
                      onSelected: editor.copyCodeContent),
                  PlatformMenuItem(
                      label: 'Auto Indent Code',
                      onSelected: editor.autoIndentCode),
                ]),
              ],
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: _checked(
                  'Quote', editor.focusedKind == BlockKind.blockquote),
              shortcut: const SingleActivator(LogicalKeyboardKey.keyQ,
                  meta: true, alt: true),
              onSelected: editor.convertToQuote,
            ),
            PlatformMenu(
              label: 'Alert',
              menus: [
                PlatformMenuItemGroup(
                  members: [
                    for (final (type, label) in [
                      ('NOTE', 'Note Block'),
                      ('TIP', 'Tip Block'),
                      ('IMPORTANT', 'Important Block'),
                      ('WARNING', 'Warning Block'),
                      ('CAUTION', 'Caution Block'),
                    ])
                      PlatformMenuItem(
                        label: label,
                        onSelected: () => editor.convertToAlert(type),
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
              label: _checked(
                  'Ordered List', editor.focusedListStyle == 'ordered'),
              shortcut: const SingleActivator(LogicalKeyboardKey.keyO,
                  meta: true, alt: true),
              onSelected: editor.convertToOrderedList,
            ),
            PlatformMenuItem(
              label: _checked(
                  'Unordered List', editor.focusedListStyle == 'unordered'),
              shortcut: const SingleActivator(LogicalKeyboardKey.keyU,
                  meta: true, alt: true),
              onSelected: editor.convertToUnorderedList,
            ),
            PlatformMenuItem(
              label:
                  _checked('Task List', editor.focusedListStyle == 'task'),
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
              label: 'Link Reference',
              onSelected: editor.insertLinkReference,
            ),
            PlatformMenuItem(
              label: 'Footnote',
              onSelected: editor.insertFootnote,
            ),
            PlatformMenuItem(
              label: 'Table of Contents',
              onSelected: editor.insertTableOfContents,
            ),
            PlatformMenuItem(
              label: 'Horizontal Line',
              onSelected: editor.insertHorizontalRule,
            ),
            PlatformMenuItem(
              label: _checked('YAML Front Matter',
                  editor.focusedKind == BlockKind.frontMatter),
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
            for (final pane in [
              SidebarPane.outline,
              SidebarPane.articles,
              SidebarPane.fileTree,
              SidebarPane.search,
            ])
              PlatformMenuItem(
                label: actions.activeSidebarPane == pane
                    ? '✓ ${pane == SidebarPane.fileTree ? 'File Tree' : pane.label}'
                    : '   ${pane == SidebarPane.fileTree ? 'File Tree' : pane.label}',
                onSelected: () => actions.selectSidebarPane(pane),
              ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label:
                  _checked('Source Mode', editor.sourceModeEnabled.value),
              shortcut:
                  const SingleActivator(LogicalKeyboardKey.slash, meta: true),
              onSelected: editor.toggleSourceMode,
            ),
            PlatformMenuItem(
              label:
                  editor.focusModeEnabled ? '✓ Focus Mode' : '   Focus Mode',
              shortcut: const SingleActivator(LogicalKeyboardKey.f8),
              onSelected: editor.toggleFocusMode,
            ),
            PlatformMenuItem(
              label: editor.typewriterModeEnabled
                  ? '✓ Typewriter Mode'
                  : '   Typewriter Mode',
              shortcut: const SingleActivator(LogicalKeyboardKey.f9),
              onSelected: editor.toggleTypewriterMode,
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: themeManager.zoom == 1.0
                  ? 'Actual Size'
                  : 'Actual Size (${(themeManager.zoom * 100).round()}%)',
              shortcut: const SingleActivator(LogicalKeyboardKey.digit0,
                  meta: true, shift: true),
              onSelected: themeManager.resetZoom,
            ),
            PlatformMenuItem(
              label: 'Zoom In',
              shortcut: const SingleActivator(LogicalKeyboardKey.equal,
                  meta: true, shift: true),
              onSelected: themeManager.zoomIn,
            ),
            PlatformMenuItem(
              label: 'Zoom Out',
              shortcut: const SingleActivator(LogicalKeyboardKey.minus,
                  meta: true, shift: true),
              onSelected: themeManager.zoomOut,
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
            PlatformMenuItem(
              label: 'Show Next Tab',
              shortcut: const SingleActivator(LogicalKeyboardKey.bracketRight,
                  meta: true, shift: true),
              onSelected: actions.nextTab,
            ),
            PlatformMenuItem(
              label: 'Show Previous Tab',
              shortcut: const SingleActivator(LogicalKeyboardKey.bracketLeft,
                  meta: true, shift: true),
              onSelected: actions.previousTab,
            ),
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
    PlatformMenu(
      label: 'Help',
      menus: [
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
                label: 'Quick Start', onSelected: actions.openQuickStart),
            PlatformMenuItem(
                label: 'Markdown Reference',
                onSelected: actions.openMarkdownReference),
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
              onPressed: actions.newTab,
              shortcut: cmd(LogicalKeyboardKey.keyT),
              child: const Text('New Tab'),
            ),
            MenuItemButton(
              onPressed: actions.closeTab,
              shortcut: cmd(LogicalKeyboardKey.keyW),
              child: const Text('Close Tab'),
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
            MenuItemButton(
              onPressed: actions.openQuickly,
              shortcut: cmd(LogicalKeyboardKey.keyO, shift: true),
              child: const Text('Open Quickly…'),
            ),
            SubmenuButton(
              menuChildren: [
                if (workspace.lastClosedFile != null) ...[
                  MenuItemButton(
                    onPressed: () =>
                        actions.openRecent(workspace.lastClosedFile!),
                    child: const Text('Reopen Closed File'),
                  ),
                  const Divider(height: 8),
                ],
                if (recents.isEmpty)
                  const MenuItemButton(child: Text('No Recent Files'))
                else
                  for (final path in recents)
                    MenuItemButton(
                      onPressed: () => actions.openRecent(path),
                      child: Text(p.basename(path)),
                    ),
                if (recents.isNotEmpty) ...[
                  const Divider(height: 8),
                  MenuItemButton(
                    onPressed: () => workspace.clearRecentFiles(),
                    child: const Text('Clear Items'),
                  ),
                ],
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
            if (actions.hasFilePath) ...[
              const Divider(height: 8),
              MenuItemButton(
                  onPressed: actions.revealFile,
                  child: const Text('Reveal in File Manager')),
              MenuItemButton(
                  onPressed: actions.duplicateFile,
                  child: const Text('Duplicate')),
              MenuItemButton(
                  onPressed: actions.renameFile,
                  child: const Text('Rename…')),
              MenuItemButton(
                  onPressed: actions.deleteFile,
                  child: const Text('Move to Trash…')),
            ],
            const Divider(height: 8),
            MenuItemButton(
              onPressed: actions.toggleAutosave,
              leadingIcon: actions.autosave
                  ? const Icon(Icons.check, size: 16)
                  : const SizedBox(width: 16),
              child: const Text('Autosave'),
            ),
            const Divider(height: 8),
            MenuItemButton(
              onPressed: actions.share,
              child: const Text('Share…'),
            ),
            MenuItemButton(
              onPressed: actions.importFile,
              child: const Text('Import…'),
            ),
            SubmenuButton(
              menuChildren: [
                MenuItemButton(
                    onPressed: actions.exportPdf,
                    child: const Text('PDF…')),
                MenuItemButton(
                    onPressed: actions.exportHtml,
                    child: const Text('HTML…')),
                MenuItemButton(
                    onPressed: actions.exportImage,
                    child: const Text('Image…')),
                const Divider(height: 8),
                MenuItemButton(
                    onPressed: () => actions.exportPandoc('docx'),
                    child: const Text('Word (.docx)…')),
                MenuItemButton(
                    onPressed: () => actions.exportPandoc('odt'),
                    child: const Text('OpenDocument (.odt)…')),
                MenuItemButton(
                    onPressed: () => actions.exportPandoc('epub'),
                    child: const Text('Epub (.epub)…')),
                MenuItemButton(
                    onPressed: () => actions.exportPandoc('tex'),
                    child: const Text('LaTeX (.tex)…')),
                MenuItemButton(
                    onPressed: () => actions.exportPandoc('rtf'),
                    child: const Text('RTF (.rtf)…')),
              ],
              child: const Text('Export'),
            ),
            MenuItemButton(
              onPressed: actions.print,
              shortcut: cmd(LogicalKeyboardKey.keyP),
              child: const Text('Print…'),
            ),
            const Divider(height: 8),
            MenuItemButton(
              onPressed: actions.preferences,
              shortcut: cmd(LogicalKeyboardKey.comma),
              child: const Text('Settings…'),
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
            // No shortcut property on these: the focused field already owns
            // Ctrl+X/C/V/A natively; the items exist for mouse access.
            MenuItemButton(
              onPressed: () => _dispatchTextIntent(
                  CopySelectionTextIntent.cut(SelectionChangedCause.keyboard)),
              child: const Text('Cut'),
            ),
            MenuItemButton(
              onPressed: () =>
                  _dispatchTextIntent(CopySelectionTextIntent.copy),
              child: const Text('Copy'),
            ),
            MenuItemButton(
              onPressed: actions.paste,
              child: const Text('Paste'),
            ),
            MenuItemButton(
              onPressed: () => _dispatchTextIntent(
                  const SelectAllTextIntent(SelectionChangedCause.keyboard)),
              child: const Text('Select All'),
            ),
            const Divider(height: 8),
            MenuItemButton(
                onPressed: editor.copyAsMarkdown,
                shortcut: cmd(LogicalKeyboardKey.keyC, shift: true),
                child: const Text('Copy as Markdown')),
            MenuItemButton(
                onPressed: editor.copyAsPlainText,
                child: const Text('Copy as Plain Text')),
            MenuItemButton(
                onPressed: editor.copyAsHtml,
                child: const Text('Copy as HTML Code')),
            MenuItemButton(
                onPressed: () => editor.pasteAsPlainText(),
                shortcut: cmd(LogicalKeyboardKey.keyV, shift: true),
                child: const Text('Paste as Plain Text')),
            const Divider(height: 8),
            SubmenuButton(
              menuChildren: [
                MenuItemButton(
                    onPressed: editor.selectWord,
                    child: const Text('Select Word')),
                MenuItemButton(
                    onPressed: editor.selectLine,
                    child: const Text('Select Line')),
                MenuItemButton(
                    onPressed: editor.selectBlock,
                    child: const Text('Select Paragraph / Block')),
                MenuItemButton(
                    onPressed: editor.selectStyledScope,
                    child: const Text('Select Styled Scope')),
                const Divider(height: 8),
                MenuItemButton(
                    onPressed: editor.jumpToTop,
                    child: const Text('Jump to Top')),
                MenuItemButton(
                    onPressed: editor.jumpToBottom,
                    child: const Text('Jump to Bottom')),
              ],
              child: const Text('Selection'),
            ),
            SubmenuButton(
              menuChildren: [
                MenuItemButton(
                    onPressed: editor.deleteBlock,
                    child: const Text('Delete Paragraph / Block')),
                MenuItemButton(
                    onPressed: editor.deleteLine,
                    child: const Text('Delete Line')),
                MenuItemButton(
                    onPressed: editor.deleteStyledScope,
                    child: const Text('Delete Styled Scope')),
                MenuItemButton(
                    onPressed: editor.deleteWord,
                    child: const Text('Delete Word')),
              ],
              child: const Text('Delete Range'),
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
              onPressed: editor.toggleUnderline,
              shortcut: cmd(LogicalKeyboardKey.keyU),
              child: const Text('Underline'),
            ),
            MenuItemButton(
              onPressed: editor.toggleComment,
              shortcut: cmd(LogicalKeyboardKey.slash, shift: true),
              child: const Text('Comment'),
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
            SubmenuButton(
              menuChildren: [
                MenuItemButton(
                    onPressed: actions.insertImage,
                    child: const Text('Insert Image…')),
                MenuItemButton(
                    onPressed: actions.insertLocalImages,
                    child: const Text('Insert Local Images…')),
              ],
              child: const Text('Image'),
            ),
            MenuItemButton(
              onPressed: editor.clearFormat,
              shortcut: cmd(LogicalKeyboardKey.backslash),
              child: const Text('Clear Format'),
            ),
            const Divider(height: 8),
            SubmenuButton(
              menuChildren: [
                MenuItemButton(
                  leadingIcon: editor.docCtrl.doc.lineEnding == '\r\n'
                      ? const Icon(Icons.check, size: 16)
                      : const SizedBox(width: 16),
                  onPressed: () => editor.docCtrl.setLineEnding('\r\n'),
                  child: const Text('Windows Line Endings (CRLF)'),
                ),
                MenuItemButton(
                  leadingIcon: editor.docCtrl.doc.lineEnding == '\n'
                      ? const Icon(Icons.check, size: 16)
                      : const SizedBox(width: 16),
                  onPressed: () => editor.docCtrl.setLineEnding('\n'),
                  child: const Text('Unix Line Endings (LF)'),
                ),
                const Divider(height: 8),
                MenuItemButton(
                  leadingIcon: editor.docCtrl.doc.hadFinalNewline
                      ? const Icon(Icons.check, size: 16)
                      : const SizedBox(width: 16),
                  onPressed: () => editor.docCtrl
                      .setFinalNewline(!editor.docCtrl.doc.hadFinalNewline),
                  child: const Text('Insert Final New Line On Save'),
                ),
              ],
              child: const Text('Line Endings'),
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
                leadingIcon: _checkIcon(editor.focusedHeadingLevel == n),
                child: Text('Heading $n'),
              ),
            MenuItemButton(
              onPressed: () => editor.setHeadingLevel(0),
              shortcut: cmd(LogicalKeyboardKey.digit0),
              leadingIcon:
                  _checkIcon(editor.focusedKind == BlockKind.paragraph),
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
            SubmenuButton(
              menuChildren: [
                MenuItemButton(
                  onPressed: actions.insertTable,
                  child: const Text('Insert Table…'),
                ),
                const Divider(height: 8),
                MenuItemButton(
                    onPressed: editor.addTableRowAbove,
                    child: const Text('Add Row Above')),
                MenuItemButton(
                    onPressed: editor.addTableRowBelow,
                    child: const Text('Add Row Below')),
                MenuItemButton(
                    onPressed: editor.addTableColumnBefore,
                    child: const Text('Add Column Before')),
                MenuItemButton(
                    onPressed: editor.addTableColumnAfter,
                    child: const Text('Add Column After')),
                const Divider(height: 8),
                MenuItemButton(
                    onPressed: editor.moveTableColumnLeft,
                    child: const Text('Move Column Left')),
                MenuItemButton(
                    onPressed: editor.moveTableColumnRight,
                    child: const Text('Move Column Right')),
                const Divider(height: 8),
                MenuItemButton(
                    onPressed: editor.deleteTableRow,
                    child: const Text('Delete Row')),
                MenuItemButton(
                    onPressed: editor.deleteTableColumn,
                    child: const Text('Delete Column')),
                const Divider(height: 8),
                MenuItemButton(
                    onPressed: editor.copyTable,
                    child: const Text('Copy Table')),
                MenuItemButton(
                    onPressed: editor.deleteTable,
                    child: const Text('Delete Table')),
              ],
              child: const Text('Table'),
            ),
            MenuItemButton(
              onPressed: editor.convertToCodeFence,
              leadingIcon: _checkIcon(
                  editor.focusedKind == BlockKind.fencedCode ||
                      editor.focusedKind == BlockKind.indentedCode),
              child: const Text('Code Fences'),
            ),
            MenuItemButton(
              onPressed: editor.convertToMathBlock,
              leadingIcon:
                  _checkIcon(editor.focusedKind == BlockKind.mathBlock),
              child: const Text('Math Block'),
            ),
            SubmenuButton(
              menuChildren: [
                MenuItemButton(
                    onPressed: editor.copyCodeContent,
                    child: const Text('Copy Code Content')),
                MenuItemButton(
                    onPressed: editor.autoIndentCode,
                    child: const Text('Auto Indent Code')),
              ],
              child: const Text('Code Tools'),
            ),
            MenuItemButton(
              onPressed: editor.convertToQuote,
              leadingIcon:
                  _checkIcon(editor.focusedKind == BlockKind.blockquote),
              child: const Text('Quote'),
            ),
            SubmenuButton(
              menuChildren: [
                for (final (type, label) in [
                  ('NOTE', 'Note Block'),
                  ('TIP', 'Tip Block'),
                  ('IMPORTANT', 'Important Block'),
                  ('WARNING', 'Warning Block'),
                  ('CAUTION', 'Caution Block'),
                ])
                  MenuItemButton(
                    onPressed: () => editor.convertToAlert(type),
                    child: Text(label),
                  ),
              ],
              child: const Text('Alert'),
            ),
            const Divider(height: 8),
            MenuItemButton(
              onPressed: editor.convertToOrderedList,
              leadingIcon: _checkIcon(editor.focusedListStyle == 'ordered'),
              child: const Text('Ordered List'),
            ),
            MenuItemButton(
              onPressed: editor.convertToUnorderedList,
              leadingIcon:
                  _checkIcon(editor.focusedListStyle == 'unordered'),
              child: const Text('Unordered List'),
            ),
            MenuItemButton(
              onPressed: editor.convertToTaskList,
              leadingIcon: _checkIcon(editor.focusedListStyle == 'task'),
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
              onPressed: editor.insertLinkReference,
              child: const Text('Link Reference'),
            ),
            MenuItemButton(
              onPressed: editor.insertFootnote,
              child: const Text('Footnote'),
            ),
            MenuItemButton(
              onPressed: editor.insertTableOfContents,
              child: const Text('Table of Contents'),
            ),
            MenuItemButton(
              onPressed: editor.insertHorizontalRule,
              child: const Text('Horizontal Line'),
            ),
            MenuItemButton(
              onPressed: editor.insertFrontMatter,
              leadingIcon:
                  _checkIcon(editor.focusedKind == BlockKind.frontMatter),
              child: const Text('YAML Front Matter'),
            ),
          ],
          child: const MenuAcceleratorLabel('&Paragraph'),
        ),
        SubmenuButton(
          menuChildren: [
            for (final pane in [
              SidebarPane.outline,
              SidebarPane.articles,
              SidebarPane.fileTree,
              SidebarPane.search,
            ])
              MenuItemButton(
                leadingIcon: actions.activeSidebarPane == pane
                    ? const Icon(Icons.check, size: 16)
                    : const SizedBox(width: 16),
                onPressed: () => actions.selectSidebarPane(pane),
                child: Text(
                    pane == SidebarPane.fileTree ? 'File Tree' : pane.label),
              ),
            const Divider(height: 8),
            MenuItemButton(
              onPressed: actions.toggleSidebar,
              shortcut: cmd(LogicalKeyboardKey.keyL, shift: true),
              child: const Text('Toggle Sidebar'),
            ),
            const Divider(height: 8),
            MenuItemButton(
              onPressed: editor.toggleSourceMode,
              shortcut: cmd(LogicalKeyboardKey.slash),
              leadingIcon: _checkIcon(editor.sourceModeEnabled.value),
              child: const Text('Source Mode'),
            ),
            MenuItemButton(
              onPressed: editor.toggleFocusMode,
              shortcut: const SingleActivator(LogicalKeyboardKey.f8),
              leadingIcon: editor.focusModeEnabled
                  ? const Icon(Icons.check, size: 16)
                  : const SizedBox(width: 16),
              child: const Text('Focus Mode'),
            ),
            MenuItemButton(
              onPressed: editor.toggleTypewriterMode,
              shortcut: const SingleActivator(LogicalKeyboardKey.f9),
              leadingIcon: editor.typewriterModeEnabled
                  ? const Icon(Icons.check, size: 16)
                  : const SizedBox(width: 16),
              child: const Text('Typewriter Mode'),
            ),
            const Divider(height: 8),
            MenuItemButton(
              onPressed: themeManager.resetZoom,
              child: Text(themeManager.zoom == 1.0
                  ? 'Actual Size'
                  : 'Actual Size (${(themeManager.zoom * 100).round()}%)'),
            ),
            MenuItemButton(
              onPressed: themeManager.zoomIn,
              shortcut: cmd(LogicalKeyboardKey.equal, shift: true),
              child: const Text('Zoom In'),
            ),
            MenuItemButton(
              onPressed: themeManager.zoomOut,
              shortcut: cmd(LogicalKeyboardKey.minus, shift: true),
              child: const Text('Zoom Out'),
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
        SubmenuButton(
          menuChildren: [
            MenuItemButton(
                onPressed: actions.openQuickStart,
                child: const Text('Quick Start')),
            MenuItemButton(
                onPressed: actions.openMarkdownReference,
                child: const Text('Markdown Reference')),
          ],
          child: const MenuAcceleratorLabel('&Help'),
        ),
      ],
    );
  }
}
