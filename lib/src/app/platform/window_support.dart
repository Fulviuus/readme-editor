/// Native window integration (window_manager) behind a conditional import so
/// the app still compiles for web (WEB-COMPILE RULE, docs/ARCHITECTURE.md).
///
/// The no-op stub is the default; `dart.library.io` swaps in the desktop
/// implementation. Callers additionally guard call sites with `kIsWeb`.
library;

export 'window_support_stub.dart'
    if (dart.library.io) 'window_support_io.dart';
