/// Web build: no external processes, so no pandoc.
library;

class PandocException implements Exception {
  PandocException(this.message);
  final String message;
  @override
  String toString() => message;
}

Future<String?> findPandoc({String? override}) async => null;

Future<String> pandocImport(String pandoc, String path) async =>
    throw PandocException('Pandoc is unavailable on this platform.');

Future<void> pandocExport(
        String pandoc, String markdown, String outPath, {String? title}) =>
    throw PandocException('Pandoc is unavailable on this platform.');
