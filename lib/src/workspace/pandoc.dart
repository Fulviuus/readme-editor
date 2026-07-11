/// Import/export through a user-installed pandoc executable, behind the
/// usual conditional import (the web build has no processes).
library;

export 'pandoc_stub.dart' if (dart.library.io) 'pandoc_io.dart';
