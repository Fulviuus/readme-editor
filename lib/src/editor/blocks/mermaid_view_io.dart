/// Native platforms: the fence body is typeset by the bundled mermaid
/// engine in a HEADLESS webview and captured as an image. The document
/// shows only the snapshot — a plain widget that scrolls, clicks and
/// selects like everything else (a live inline webview would swallow
/// scroll events over the diagram).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

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

class _RenderedDiagram {
  const _RenderedDiagram({this.png, this.height = 0, this.error});
  final Uint8List? png;
  final double height;
  final String? error;
}

/// Snapshot cache so scrolling a diagram out of view and back does not
/// re-run the engine. Keyed by theme-brightness, width and source.
final _cache = <String, _RenderedDiagram>{};
const _cacheCap = 24;

class MermaidBlockView extends StatefulWidget {
  const MermaidBlockView(
      {super.key, required this.block, required this.editor});

  final Block block;
  final EditorController editor;

  @override
  State<MermaidBlockView> createState() => _MermaidBlockViewState();
}

class _MermaidBlockViewState extends State<MermaidBlockView> {
  /// Keys currently being rendered (across all instances).
  static final _inFlight = <String>{};

  bool get _dark =>
      widget.editor.theme.background.computeLuminance() < 0.5;

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
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : theme.contentMaxWidth;
      final key = '${_dark ? 'd' : 'l'}|${width.round()}|${body.hashCode}';
      final cached = _cache[key];
      if (cached == null) {
        _startRender(key, body, width);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _focus,
          child: SizedBox(
            height: theme.fontSize * 6,
            width: double.infinity,
            child: Center(
              child: Text('diagram…',
                  style: theme.monoStyle.copyWith(
                      fontSize: theme.fontSize * 0.75,
                      color: theme.hintColor)),
            ),
          ),
        );
      }
      if (cached.error != null || cached.png == null) {
        return _errorFallback(theme, cached.error ?? 'diagram failed');
      }
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _focus,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(vertical: theme.fontSize * 0.4),
          alignment: Alignment.center,
          child: Image.memory(
            cached.png!,
            width: width,
            height: cached.height,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
          ),
        ),
      );
    });
  }

  Future<void> _startRender(String key, String body, double width) async {
    if (_inFlight.contains(key)) return;
    _inFlight.add(key);
    HeadlessInAppWebView? headless;
    try {
      final engineJs = await _loadMermaidJs();
      final completer = Completer<_RenderedDiagram>();
      headless = HeadlessInAppWebView(
        initialSize: Size(width, 400),
        initialSettings: InAppWebViewSettings(
          transparentBackground: true,
          supportZoom: false,
        ),
        initialData: InAppWebViewInitialData(data: _html(engineJs, body)),
        onWebViewCreated: (controller) {
          controller.addJavaScriptHandler(
            handlerName: 'mermaidSize',
            callback: (args) async {
              try {
                final h =
                    (args.first as num).toDouble().clamp(24.0, 4000.0);
                await headless?.setSize(Size(width, h));
                // One breath for the resized page to repaint.
                await Future<void>.delayed(
                    const Duration(milliseconds: 250));
                final shot = await headless?.webViewController
                    ?.takeScreenshot(
                        screenshotConfiguration: ScreenshotConfiguration(
                  compressFormat: CompressFormat.PNG,
                  snapshotWidth: width.round() * 2, // retina-crisp
                ));
                if (!completer.isCompleted) {
                  completer.complete(shot == null
                      ? const _RenderedDiagram(error: 'snapshot failed')
                      : _RenderedDiagram(png: shot, height: h));
                }
              } catch (e) {
                if (!completer.isCompleted) {
                  completer.complete(_RenderedDiagram(error: '$e'));
                }
              }
            },
          );
          controller.addJavaScriptHandler(
            handlerName: 'mermaidError',
            callback: (args) {
              if (!completer.isCompleted) {
                completer.complete(_RenderedDiagram(
                    error:
                        args.isEmpty ? 'diagram failed' : '${args.first}'));
              }
            },
          );
        },
      );
      await headless.run();
      final result = await completer.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () =>
            const _RenderedDiagram(error: 'diagram render timed out'),
      );
      if (_cache.length >= _cacheCap) _cache.remove(_cache.keys.first);
      _cache[key] = result;
    } catch (e) {
      _cache[key] = _RenderedDiagram(error: '$e');
    } finally {
      unawaited(headless?.dispose() ?? Future<void>.value());
      _inFlight.remove(key);
    }
    if (mounted) setState(() {});
  }

  /// Invalid diagram source: the plain code box plus the engine's message.
  Widget _errorFallback(ReadmeTheme theme, String message) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CodeBlockView(block: widget.block, editor: widget.editor),
        Padding(
          padding: EdgeInsets.only(top: theme.fontSize * 0.25),
          child: Text(
            message,
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
