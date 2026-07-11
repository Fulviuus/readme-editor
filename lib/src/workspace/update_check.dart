/// "Check for Updates…" against the project's release feed, behind the
/// usual conditional import.
library;

export 'update_check_stub.dart' if (dart.library.io) 'update_check_io.dart';

/// The running app's version (kept in sync with pubspec.yaml).
const String appVersion = '1.0.0';

sealed class UpdateResult {
  const UpdateResult();
}

class UpToDate extends UpdateResult {
  const UpToDate();
}

class UpdateAvailable extends UpdateResult {
  const UpdateAvailable(this.version, this.url);
  final String version;
  final String url;
}

class UpdateCheckFailed extends UpdateResult {
  const UpdateCheckFailed(this.reason);
  final String reason;
}
