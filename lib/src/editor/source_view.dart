/// Whole-document source mode (Cmd+/): one plain-text monospace editor over
/// the serialized markdown. No live re-parsing while typing — the edited
/// text is committed as a single [DocumentController.replaceAll] when source
/// mode exits (or this view disposes), exactly once.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../document/document_controller.dart';
import 'editor_controller.dart';
import 'source_highlight_controller.dart';

class SourceView extends StatefulWidget {
  const SourceView({super.key, required this.editor});

  final EditorController editor;

  @override
  State<SourceView> createState() => _SourceViewState();
}

class _SourceViewState extends State<SourceView> {
  late final SourceHighlightController _text;
  final FocusNode _focus = FocusNode(debugLabel: 'source-view');
  bool _committed = false;

  // Snapshot of the document when this source session (re)armed; if the
  // document is replaced underneath us (Open/New while in source mode), the
  // stale source text must NOT be committed over the new document.
  late String _initial;
  String? _initialPath;
  late int _initialRevision;

  DocumentController get _docCtrl => widget.editor.docCtrl;

  @override
  void initState() {
    super.initState();
    _snapshot();
    _text = SourceHighlightController(text: _initial);
    widget.editor.addListener(_onEditorChanged);
    widget.editor.sourceModeEnabled.addListener(_onSourceModeChanged);
    // Let the shell flush uncommitted source edits before save/dirty checks;
    // that commit re-arms so editing can continue after e.g. Cmd+S.
    widget.editor.commitSourceMode = _commitAndRearm;
  }

  void _snapshot() {
    _initial = _docCtrl.serialize();
    _initialPath = _docCtrl.filePath;
    _initialRevision = _docCtrl.revision;
  }

  /// Theme or highlight-preference changes repaint the field.
  void _onEditorChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.editor.removeListener(_onEditorChanged);
    widget.editor.sourceModeEnabled.removeListener(_onSourceModeChanged);
    if (widget.editor.commitSourceMode == _commitAndRearm) {
      widget.editor.commitSourceMode = null;
    }
    _commit();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onSourceModeChanged() {
    if (!widget.editor.sourceModeEnabled.value) _commit();
  }

  /// Commit contract: [DocumentController.replaceAll] exactly once per
  /// session (guarded against the toggle listener and dispose both firing),
  /// only if the text actually changed, and only if the underlying document
  /// is still the one this session armed on.
  void _commit() {
    if (_committed) return;
    _committed = true;
    final documentUnchanged = _docCtrl.filePath == _initialPath &&
        _docCtrl.revision == _initialRevision &&
        _docCtrl.serialize() == _initial;
    if (documentUnchanged && _text.text != _initial) {
      _docCtrl.replaceAll(_text.text);
    }
  }

  void _commitAndRearm() {
    _commit();
    _snapshot();
    _committed = false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.editor.theme;
    final meta = defaultTargetPlatform == TargetPlatform.macOS;
    final style = theme.monoStyle.copyWith(
      color: theme.foreground,
      fontSize: theme.fontSize,
      height: 1.6,
    );
    _text
      ..theme = theme
      ..highlightEnabled = widget.editor.sourceHighlightEnabled;
    return ColoredBox(
      color: theme.background,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          SingleActivator(LogicalKeyboardKey.slash,
              meta: meta, control: !meta): widget.editor.toggleSourceMode,
        },
        child: Theme(
          data: Theme.of(context).copyWith(
            textSelectionTheme: TextSelectionThemeData(
              cursorColor: theme.caret,
              selectionColor: theme.selectionBackground,
              selectionHandleColor: theme.accent,
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'SOURCE MODE — ${meta ? 'Cmd' : 'Ctrl'}+/ to return',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.2,
                    color: theme.hintColor,
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(40, 16, 40, 0),
                      child: TextField(
                        controller: _text,
                        focusNode: _focus,
                        autofocus: true,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        keyboardType: TextInputType.multiline,
                        style: style,
                        cursorColor: theme.caret,
                        decoration: const InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
