/// Desktop implementation: renders local image files with dart:io.
library;

import 'dart:io';

import 'package:flutter/widgets.dart';

/// Renders a local image file; falls back to [placeholder] when the file is
/// missing or cannot be decoded.
Widget buildLocalImage(String path, String alt, Widget Function() placeholder) {
  return Image.file(
    File(path),
    semanticLabel: alt.isEmpty ? null : alt,
    errorBuilder: (context, error, stackTrace) => placeholder(),
  );
}
