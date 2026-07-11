/// Native spell checking behind a conditional import: on macOS the system
/// spell checker is reached over a platform channel; everywhere else the
/// stub reports `supported == false` and the editor never asks again.
library;

export 'spell_checker_stub.dart'
    if (dart.library.io) 'spell_checker_io.dart';
