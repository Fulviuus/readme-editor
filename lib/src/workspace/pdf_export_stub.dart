/// Web build of the PDF helpers — no file-save dialog available.
library;

import '../document/document.dart';
import '../theme/readme_theme.dart';

Future<bool> exportPdfDialog(
  Document doc,
  ReadmeTheme theme, {
  String? title,
  String? suggestedName,
}) async =>
    false;

Future<void> printDocument(
  Document doc,
  ReadmeTheme theme, {
  String? title,
}) async {}

const bool supportsPdf = false;
