/// Native platforms: the fence body is typeset by the bundled mermaid
/// engine inside a transparent inline webview. The webview is display-only
/// (pointer events ignored) so clicking a diagram focuses the block for
/// editing, exactly like every other rendered block.
library;

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../document/block.dart';
import '../../theme/readme_theme.dart';
import '../editor_controller.dart';
import 'code_block.dart';

/// Whether this platform renders mermaid diagrams: the webview plugin
/// covers macOS/Windows (WebView2)/iOS/Android but not Linux desktop.
final bool mermaidSupported = !Platform.isLinux;

/// The engine is ~2.7 MB of JS; load it from the bundle once.
Future<String>? _mermaidJs;
Future<String> _loadMermaidJs() =>
    _mermaidJs ??= rootBundle.loadString('assets/js/mermaid.min.js');

class MermaidBlockView extends StatefulWidget {
  const MermaidBlockView(
      {super.key, required this.block, required this.editor});

  final Block block;
  final EditorController editor;

  @override
  State<MermaidBlockView> createState() => _MermaidBlockViewState();
}

class _MermaidBlockViewState extends State<MermaidBlockView> {
  double? _height;
  String? _error;

  bool get _dark =>
      widget.editor.theme.background.computeLuminance() < 0.5;

  @override
  void didUpdateWidget(MermaidBlockView old) {
    super.didUpdateWidget(old);
    if (old.block.codeBody != widget.block.codeBody) {
      _height = null;
      _error = null;
    }
  }

  void _focus() {
    final firstNl = widget.block.source.indexOf('\n');
    widget.editor.focusBlock(widget.block.id,
        offset: firstNl < 0 ? widget.block.source.length : firstNl + 1);
  }

  @override
  Widget build(BuildContext context) {
    if (!mermaidSupported) {
      return CodeBlockView(block: widget.block, editor: widget.editor);
    }
    final theme = widget.editor.theme;
    final body = widget.block.codeBody;
    if (_error != null) return _errorFallback(theme);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _focus,
      child: SizedBox(
        height: _height ?? theme.fontSize * 6,
        width: double.infinity,
        child: IgnorePointer(
          child: FutureBuilder<String>(
            future: _loadMermaidJs(),
            builder: (context, snap) {
              if (!snap.hasData) return const SizedBox.shrink();
              return InAppWebView(
                // Recreate the page when the diagram or theme changes.
                key: ValueKey('${_dark ? 'd' : 'l'}:${body.hashCode}'),
                initialSettings: InAppWebViewSettings(
                  transparentBackground: true,
                  disableContextMenu: true,
                  supportZoom: false,
                ),
                initialData:
                    InAppWebViewInitialData(data: _html(snap.data!, body)),
                onWebViewCreated: (controller) {
                  controller.addJavaScriptHandler(
                    handlerName: 'mermaidSize',
                    callback: (args) {
                      final h = (args.first as num).toDouble();
                      if (mounted && h > 0) {
                        setState(() => _height = h + theme.fontSize * 0.8);
                      }
                    },
                  );
                  controller.addJavaScriptHandler(
                    handlerName: 'mermaidError',
                    callback: (args) {
                      if (mounted) {
                        setState(() => _error = args.firstOrNull?.toString());
                      }
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  /// Invalid diagram source: the plain code box plus the engine's message.
  Widget _errorFallback(ReadmeTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CodeBlockView(block: widget.block, editor: widget.editor),
        Padding(
          padding: EdgeInsets.only(top: theme.fontSize * 0.25),
          child: Text(
            _error!,
            style: theme.monoStyle.copyWith(
                fontSize: theme.fontSize * 0.7, color: theme.hintColor),
          ),
        ),
      ],
    );
  }

  String _html(String engineJs, String code) {
    final diagramTheme = _dark ? 'dark' : 'default';
    // callHandler only exists after the platform-ready event; the page may
    // fire it before or after our listener attaches, so poll-guard both.
    return '''
<!doctype html><html><head><meta charset="utf-8">
<style>html,body{margin:0;padding:0;background:transparent;overflow:hidden}
svg{display:block;margin:0 auto}</style></head><body>
<div id="out"></div>
<script>$engineJs</script>
<script>
var started = false;
function run() {
  if (started || !window.flutter_inappwebview || !window.flutter_inappwebview.callHandler) return;
  started = true;
  mermaid.initialize({startOnLoad:false, theme:'$diagramTheme', securityLevel:'strict'});
  mermaid.render('diagram', ${jsonEncode(code)}).then(function(r){
    document.getElementById('out').innerHTML = r.svg;
    var s = document.querySelector('svg');
    window.flutter_inappwebview.callHandler('mermaidSize',
        s ? s.getBoundingClientRect().height : 0);
  }).catch(function(e){
    window.flutter_inappwebview.callHandler('mermaidError',
        String(e && e.message ? e.message : e));
  });
}
window.addEventListener('flutter_inappwebviewPlatformReady', run);
var poll = setInterval(function(){ run(); if (started) clearInterval(poll); }, 50);
</script></body></html>''';
  }
}
