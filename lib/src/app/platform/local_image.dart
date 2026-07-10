/// Local-filesystem image loading behind a conditional import; the web build
/// gets a stub that always shows the placeholder (WEB-COMPILE RULE,
/// docs/ARCHITECTURE.md).
library;

export 'local_image_stub.dart' if (dart.library.io) 'local_image_io.dart';
