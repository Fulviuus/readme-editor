/// PDF export and printing behind a conditional import so the web build
/// (which has no file-save dialog and a different Printing surface) still
/// compiles. The desktop implementation renders the themed HTML export
/// through package:printing.
library;

export 'pdf_export_stub.dart'
    if (dart.library.io) 'pdf_export_io.dart';
