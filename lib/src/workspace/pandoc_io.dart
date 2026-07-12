/// Native platforms: shells out to a user-installed pandoc. The output
/// format is inferred from the target file's extension, the input format
/// from the source file's — both by pandoc itself.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

class PandocException implements Exception {
  PandocException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Absolute path of the pandoc executable, or null if not installed.
/// A user-configured [override] (Preferences > Export) wins; otherwise the
/// usual install locations are probed because GUI apps don't inherit a
/// login shell's PATH.
Future<String?> findPandoc({String? override}) async {
  if (override != null && override.isNotEmpty) {
    if (File(override).existsSync()) return override;
    return null; // an explicit-but-wrong path should fail loudly, not mask
  }
  for (final candidate in [
    '/opt/homebrew/bin/pandoc',
    '/usr/local/bin/pandoc',
    '/usr/bin/pandoc',
  ]) {
    if (File(candidate).existsSync()) return candidate;
  }
  try {
    final r = await Process.run(
        Platform.isWindows ? 'where' : 'which', ['pandoc']);
    final out = (r.stdout as String).trim().split('\n').first.trim();
    if (r.exitCode == 0 && out.isNotEmpty) return out;
  } catch (_) {}
  return null;
}

/// Converts [path] (docx/odt/epub/html/rtf/…) to GitHub-flavored markdown.
Future<String> pandocImport(String pandoc, String path) async {
  final r = await Process.run(pandoc, [path, '-t', 'gfm', '--wrap=none']);
  if (r.exitCode != 0) {
    throw PandocException((r.stderr as String).trim());
  }
  return r.stdout as String;
}

/// Converts [markdown] to whatever [outPath]'s extension says (.docx, .odt,
/// .epub, .tex, .rtf, …). `-s` makes text formats standalone documents;
/// binary formats always are.
Future<void> pandocExport(String pandoc, String markdown, String outPath,
    {String? title}) async {
  final dir = await Directory.systemTemp.createTemp('readme_pandoc');
  try {
    final src = File(p.join(dir.path, 'document.md'));
    await src.writeAsString(markdown);
    final r = await Process.run(pandoc, [
      '-f', 'gfm', '-s',
      if (title != null) ...['--metadata', 'title=$title'],
      src.path, '-o', outPath,
    ]);
    if (r.exitCode != 0) {
      throw PandocException((r.stderr as String).trim());
    }
  } finally {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }
}
