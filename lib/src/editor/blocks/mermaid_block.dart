/// Rendered `mermaid` fenced block: the diagram source is typeset by the
/// bundled mermaid engine inside a transparent inline webview (native
/// platforms). Platforms without a webview fall back to the plain code box.
library;

export 'mermaid_view_stub.dart' if (dart.library.io) 'mermaid_view_io.dart';
