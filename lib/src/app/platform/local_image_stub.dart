/// Web build: local files are unreachable — always show the placeholder.
library;

import 'package:flutter/widgets.dart';

/// Renders a local image file; on web this is always the [placeholder].
Widget buildLocalImage(
        String path, String alt, Widget Function() placeholder) =>
    placeholder();
