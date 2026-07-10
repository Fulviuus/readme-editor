/// Desktop PDF export / print. PDF bytes are produced by the pure-Dart
/// [renderDocumentPdf]; package:printing is used only for the native print
/// dialog (which takes ready-made PDF bytes — no WebView involved).
library;

import 'package:file_selector/file_selector.dart';
import 'package:printing/printing.dart';

import '../document/document.dart';
import '../theme/readme_theme.dart';
import 'pdf_render.dart';

/// Prompts for a `.pdf` location and writes the rendered document. Returns
/// false when cancelled.
Future<bool> exportPdfDialog(
  Document doc,
  ReadmeTheme theme, {
  String? title,
  String? suggestedName,
}) async {
  final location = await getSaveLocation(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'PDF', extensions: <String>['pdf']),
    ],
    suggestedName: suggestedName ?? 'Untitled.pdf',
  );
  if (location == null) return false;
  var path = location.path;
  if (!path.toLowerCase().endsWith('.pdf')) path = '$path.pdf';
  final bytes = await renderDocumentPdf(doc, theme, title: title);
  await XFile.fromData(bytes, mimeType: 'application/pdf').saveTo(path);
  return true;
}

/// Opens the system print dialog for the document.
Future<void> printDocument(
  Document doc,
  ReadmeTheme theme, {
  String? title,
}) async {
  await Printing.layoutPdf(
    name: title ?? 'Untitled',
    onLayout: (_) => renderDocumentPdf(doc, theme, title: title),
  );
}

const bool supportsPdf = true;
