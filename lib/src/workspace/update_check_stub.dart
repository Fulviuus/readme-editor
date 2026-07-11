/// Web build: the page itself is always the latest deploy.
library;

import 'update_check.dart';

Future<UpdateResult> checkForUpdates() async =>
    const UpdateCheckFailed('Update checks are not available on the web.');
