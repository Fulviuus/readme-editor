/// Web build: no local snapshot store.
library;

import 'file_history.dart';

Future<void> recordSnapshot(String docPath, String text) async {}

Future<List<HistoryEntry>> listSnapshots(String docPath) async => const [];

Future<String> readSnapshot(String snapshotPath) async =>
    throw UnsupportedError('History is not available on the web');
