/// Native platforms: asks the GitHub releases API for the latest tag and
/// compares it against [appVersion]. Fails soft — no releases yet (or a
/// private repository) reads as "couldn't check", never as an error dialog
/// storm.
library;

import 'dart:convert';
import 'dart:io';

import 'update_check.dart';

const _releasesApi =
    'https://api.github.com/repos/Fulviuus/readme-editor/releases/latest';
const _releasesPage = 'https://github.com/Fulviuus/readme-editor/releases';

Future<UpdateResult> checkForUpdates() async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(Uri.parse(_releasesApi));
    request.headers.set('Accept', 'application/vnd.github+json');
    final response = await request.close();
    if (response.statusCode != 200) {
      return const UpdateCheckFailed(
          'No published releases were found to compare against.');
    }
    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final tag = (json['tag_name'] as String? ?? '').replaceFirst('v', '');
    if (tag.isEmpty) {
      return const UpdateCheckFailed('The release feed had no version tag.');
    }
    return _isNewer(tag, appVersion)
        ? UpdateAvailable(tag, json['html_url'] as String? ?? _releasesPage)
        : const UpToDate();
  } on SocketException {
    return const UpdateCheckFailed('You appear to be offline.');
  } catch (e) {
    return UpdateCheckFailed('Could not check for updates: $e');
  } finally {
    client.close(force: true);
  }
}

bool _isNewer(String candidate, String current) {
  List<int> parts(String v) => [
        for (final s in v.split('.')) int.tryParse(s.trim()) ?? 0,
      ];
  final a = parts(candidate), b = parts(current);
  for (var i = 0; i < a.length || i < b.length; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}
