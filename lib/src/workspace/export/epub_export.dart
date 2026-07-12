/// Native EPUB 3 export: a zip container holding a single XHTML chapter
/// produced by the same markdown→HTML pipeline as the HTML export, styled
/// with the theme CSS. Local images are embedded and their sources
/// rewritten into the package.
library;

import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:markdown/markdown.dart' as md;

import '../../theme/readme_theme.dart';
import 'docx_export.dart' show ImageBytesResolver;
import 'export_common.dart';
import '../html_export.dart' show themeCssFor;

Uint8List buildEpub(
  String markdownSource,
  ReadmeTheme theme, {
  required String title,
  ImageBytesResolver? images,
}) {
  var body = md.markdownToHtml(
    markdownSource,
    extensionSet: md.ExtensionSet.gitHubFlavored,
  );

  // Embed local images: rewrite src into the package, collect the bytes.
  final media = <String, List<int>>{};
  final manifest = StringBuffer();
  var imgId = 0;
  body = body.replaceAllMapped(
      RegExp(r'<img([^>]*?)src="([^"]*)"([^>]*?)/?>'), (m) {
    final src = m.group(2)!;
    final bytes = images?.call(src);
    if (bytes == null) {
      return '<img${m.group(1)}src="${escapeXml(src)}"${m.group(3)}/>';
    }
    imgId++;
    final ext = _extOf(bytes);
    final name = 'media/img$imgId.$ext';
    media[name] = bytes;
    manifest.write('<item id="img$imgId" href="$name" '
        'media-type="image/${ext == 'jpg' ? 'jpeg' : ext}"/>');
    return '<img${m.group(1)}src="$name"${m.group(3)}/>';
  });
  // XHTML needs void elements self-closed; the markdown renderer already
  // self-closes br/hr/img, but input HTML passthrough may not.
  body = body.replaceAllMapped(
      RegExp(r'<(br|hr)(\s[^>]*)?>(?!</)', caseSensitive: false),
      (m) => '<${m.group(1)}${m.group(2) ?? ''}/>');
  // markdownToHtml emits unclosed <img ...> for markdown images.
  body = body.replaceAllMapped(
      RegExp(r'<img([^>]*[^/>])>', caseSensitive: false),
      (m) => '<img${m.group(1)}/>');

  final safeTitle = escapeXml(title);
  final chapter = '<?xml version="1.0" encoding="utf-8"?>\n'
      '<html xmlns="http://www.w3.org/1999/xhtml">\n'
      '<head><title>$safeTitle</title>'
      '<link rel="stylesheet" type="text/css" href="style.css"/></head>\n'
      '<body><article class="markdown-body">\n$body</article></body>\n'
      '</html>\n';

  final nav = '<?xml version="1.0" encoding="utf-8"?>\n'
      '<html xmlns="http://www.w3.org/1999/xhtml" '
      'xmlns:epub="http://www.idpf.org/2007/ops">\n'
      '<head><title>$safeTitle</title></head>\n'
      '<body><nav epub:type="toc"><ol>'
      '<li><a href="doc.xhtml">$safeTitle</a></li>'
      '</ol></nav></body></html>\n';

  final opf = '<?xml version="1.0" encoding="utf-8"?>\n'
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="uid">\n'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">\n'
      '<dc:identifier id="uid">urn:readme:$safeTitle</dc:identifier>\n'
      '<dc:title>$safeTitle</dc:title>\n'
      '<dc:language>en</dc:language>\n'
      '<meta property="dcterms:modified">2020-01-01T00:00:00Z</meta>\n'
      '</metadata>\n'
      '<manifest>\n'
      '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" '
      'properties="nav"/>\n'
      '<item id="doc" href="doc.xhtml" '
      'media-type="application/xhtml+xml"/>\n'
      '<item id="css" href="style.css" media-type="text/css"/>\n'
      '$manifest'
      '</manifest>\n'
      '<spine><itemref idref="doc"/></spine>\n'
      '</package>\n';

  const container = '<?xml version="1.0" encoding="utf-8"?>\n'
      '<container version="1.0" '
      'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">\n'
      '<rootfiles><rootfile full-path="OEBPS/content.opf" '
      'media-type="application/oebps-package+xml"/></rootfiles>\n'
      '</container>\n';

  // The mimetype entry must be first and stored uncompressed.
  final mimetype =
      ArchiveFile.string('mimetype', 'application/epub+zip')
        ..compression = CompressionType.none;
  final archive = Archive()
    ..add(mimetype)
    ..add(ArchiveFile.string('META-INF/container.xml', container))
    ..add(ArchiveFile.string('OEBPS/content.opf', opf))
    ..add(ArchiveFile.string('OEBPS/nav.xhtml', nav))
    ..add(ArchiveFile.string('OEBPS/doc.xhtml', chapter))
    ..add(ArchiveFile.string('OEBPS/style.css', themeCssFor(theme)));
  media.forEach((name, bytes) {
    archive.add(ArchiveFile.bytes('OEBPS/$name', bytes));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String _extOf(List<int> b) {
  if (b.length > 3 && b[0] == 0x89 && b[1] == 0x50) return 'png';
  if (b.length > 3 && b[0] == 0x47 && b[1] == 0x49) return 'gif';
  return 'jpg';
}
