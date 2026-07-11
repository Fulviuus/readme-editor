/// Native platforms: snapshots live under
/// `<app support>/history/<document-key>/<millis>.md`, capped at the newest
/// [_maxSnapshots] per document. The key hashes the absolute path, so moved
/// or renamed documents simply start a fresh history.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'file_history.dart';

const _maxSnapshots = 20;

String _keyFor(String docPath) {
  // FNV-1a, hex — stable across runs, filename-safe.
  var hash = 0xcbf29ce484222325;
  for (final unit in docPath.codeUnits) {
    hash = ((hash ^ unit) * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

Future<Directory> _dirFor(String docPath) async {
  final support = await getApplicationSupportDirectory();
  return Directory(p.join(support.path, 'history', _keyFor(docPath)));
}

Future<void> recordSnapshot(String docPath, String text) async {
  try {
    final dir = await _dirFor(docPath);
    await dir.create(recursive: true);
    final entries = await listSnapshots(docPath);
    // Skip when nothing changed since the newest snapshot.
    if (entries.isNotEmpty &&
        await File(entries.first.path).readAsString() == text) {
      return;
    }
    final stamp = DateTime.now().millisecondsSinceEpoch;
    await File(p.join(dir.path, '$stamp.md')).writeAsString(text);
    for (final old in entries.skip(_maxSnapshots - 1)) {
      try {
        await File(old.path).delete();
      } catch (_) {}
    }
  } catch (_) {
    // History is best-effort; a failed snapshot must never fail the save.
  }
}

/// Newest first.
Future<List<HistoryEntry>> listSnapshots(String docPath) async {
  try {
    final dir = await _dirFor(docPath);
    if (!await dir.exists()) return const [];
    final entries = <HistoryEntry>[];
    await for (final f in dir.list()) {
      if (f is! File) continue;
      final millis = int.tryParse(p.basenameWithoutExtension(f.path));
      if (millis == null) continue;
      entries.add(HistoryEntry(
        DateTime.fromMillisecondsSinceEpoch(millis),
        f.path,
        await f.length(),
      ));
    }
    entries.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return entries;
  } catch (_) {
    return const [];
  }
}

Future<String> readSnapshot(String snapshotPath) =>
    File(snapshotPath).readAsString();
