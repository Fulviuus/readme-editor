/// Compact find/replace bar (Cmd+F): find field with a live 'i/n' match
/// counter, prev/next cycling, case toggle, and an expandable replace row.
/// Owns its [FindController]. Inside the bar: Enter = next, Shift+Enter =
/// previous, Esc = close.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/readme_theme.dart';
import 'editor_controller.dart';
import 'find_controller.dart';

class FindBar extends StatefulWidget {
  const FindBar({super.key, required this.editor});

  final EditorController editor;

  @override
  State<FindBar> createState() => _FindBarState();
}

class _FindBarState extends State<FindBar> {
  late final FindController _find = FindController(widget.editor);
  final _queryCtrl = TextEditingController();
  final _replaceCtrl = TextEditingController();
  final _queryFocus = FocusNode(debugLabel: 'find-query');
  final _replaceFocus = FocusNode(debugLabel: 'find-replace');
  bool _showReplace = false;

  @override
  void dispose() {
    _find.dispose();
    _queryCtrl.dispose();
    _replaceCtrl.dispose();
    _queryFocus.dispose();
    _replaceFocus.dispose();
    super.dispose();
  }

  /// Jumping to a match focuses the block (the selection lives in its
  /// TextField); pull keyboard focus back afterwards so Enter keeps cycling
  /// from the bar.
  void _run(VoidCallback action, {FocusNode? refocus}) {
    final target =
        refocus ?? (_replaceFocus.hasFocus ? _replaceFocus : _queryFocus);
    action();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) target.requestFocus();
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _find.close();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _run(HardwareKeyboard.instance.isShiftPressed
          ? _find.previous
          : _find.next);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.editor.theme;
    return Focus(
      onKeyEvent: _onKey,
      child: Material(
        color: theme.sidebarBackground,
        child: Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.hr)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Theme(
            data: Theme.of(context).copyWith(
              textSelectionTheme: TextSelectionThemeData(
                cursorColor: theme.caret,
                selectionColor: theme.selectionBackground,
              ),
            ),
            child: ListenableBuilder(
              listenable: _find,
              builder: (context, _) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _findRow(theme),
                  if (_showReplace) ...[
                    const SizedBox(height: 6),
                    _replaceRow(theme),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _findRow(ReadmeTheme theme) {
    final hasMatches = _find.matches.isNotEmpty;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _iconButton(
          _showReplace ? Icons.expand_more : Icons.chevron_right,
          _showReplace ? 'Hide replace' : 'Show replace',
          () => setState(() => _showReplace = !_showReplace),
        ),
        const SizedBox(width: 4),
        _field(
          controller: _queryCtrl,
          focusNode: _queryFocus,
          hint: 'Find',
          autofocus: true,
          onChanged: _find.search,
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 56,
          child: Text(
            _counterText(),
            style: TextStyle(fontSize: 12, color: theme.sidebarForeground),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _iconButton(Icons.keyboard_arrow_up, 'Previous match (Shift+Enter)',
            hasMatches ? () => _run(_find.previous) : null),
        _iconButton(Icons.keyboard_arrow_down, 'Next match (Enter)',
            hasMatches ? () => _run(_find.next) : null),
        const SizedBox(width: 4),
        _caseToggle(theme),
        const SizedBox(width: 4),
        _iconButton(Icons.close, 'Close (Esc)', _find.close),
      ],
    );
  }

  Widget _replaceRow(ReadmeTheme theme) {
    final canReplace = _find.matches.isNotEmpty;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 32), // aligns with the find field
        _field(
          controller: _replaceCtrl,
          focusNode: _replaceFocus,
          hint: 'Replace with',
          onChanged: (v) => _find.replacement = v,
        ),
        const SizedBox(width: 8),
        _textButton(
            'Replace',
            canReplace
                ? () => _run(_find.replaceCurrent, refocus: _replaceFocus)
                : null),
        const SizedBox(width: 4),
        _textButton('Replace all', canReplace ? _find.replaceAll : null),
      ],
    );
  }

  String _counterText() {
    if (_find.query.isEmpty) return '';
    final n = _find.matches.length;
    if (n == 0) return '0/0';
    return '${_find.currentIndex < 0 ? 0 : _find.currentIndex + 1}/$n';
  }

  Widget _field({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required ValueChanged<String> onChanged,
    bool autofocus = false,
  }) {
    final theme = widget.editor.theme;
    return SizedBox(
      width: 220,
      height: 28,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        onChanged: onChanged,
        style: TextStyle(color: theme.foreground, fontSize: 13),
        cursorColor: theme.caret,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: theme.hintColor, fontSize: 13),
          isDense: true,
          filled: true,
          fillColor: theme.background,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: BorderSide(color: theme.hr),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: BorderSide(color: theme.accent, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _caseToggle(ReadmeTheme theme) {
    final active = _find.caseSensitive;
    return Tooltip(
      message: 'Match case',
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () {
          _find.caseSensitive = !active;
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: active ? theme.sidebarActiveBackground : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'Aa',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? theme.accent : theme.sidebarForeground,
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconButton(IconData icon, String tooltip, VoidCallback? onPressed) {
    final theme = widget.editor.theme;
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon),
      iconSize: 16,
      color: theme.sidebarForeground,
      disabledColor: theme.hintColor,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      splashRadius: 14,
    );
  }

  Widget _textButton(String label, VoidCallback? onPressed) {
    final theme = widget.editor.theme;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: theme.accent,
        disabledForegroundColor: theme.hintColor,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 28),
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label),
    );
  }
}
