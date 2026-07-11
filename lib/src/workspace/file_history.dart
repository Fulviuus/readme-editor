/// Local save-history snapshots (a lightweight stand-in for system file
/// versioning): every successful save records a timestamped copy under the
/// app-support folder, and File > Revert To… restores one.
library;

export 'file_history_stub.dart' if (dart.library.io) 'file_history_io.dart';

/// One recorded save of a document.
class HistoryEntry {
  const HistoryEntry(this.savedAt, this.path, this.sizeBytes);
  final DateTime savedAt;
  final String path;
  final int sizeBytes;
}
