/// Clipboard image access behind a conditional import (Flutter's Clipboard
/// API is text-only; the native side reads the pasteboard).
library;

export 'clipboard_image_stub.dart'
    if (dart.library.io) 'clipboard_image_io.dart';
