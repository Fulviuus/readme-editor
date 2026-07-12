import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme/src/editor/source_highlight_controller.dart';
import 'package:readme/src/theme/readme_theme.dart';

ReadmeTheme theme() => ReadmeTheme.fromJson('t', {
      'blockquoteBorder': '#dfe2e5',
      'link': '#4183C4',
      'linkHover': '#4183C4',
      'hr': '#e7e7e7',
      'checkboxAccent': '#4183C4',
      'sidebarBackground': '#fafafa',
      'sidebarForeground': '#777777',
      'sidebarActiveBackground': '#eeeeee',
    });

const _md = '''
# Title with **bold**

Plain paragraph with *italic*, `code`, a [link](https://x.y) and \$x^2\$.

> quoted line

- item one
- [x] task

| a | b |
|---|---|
| 1 | 2 |

```dart
void main() {}
```

---

[ref]: https://example.com
last line''';

String plain(InlineSpan span) {
  final buf = StringBuffer();
  span.visitChildren((s) {
    if (s is TextSpan && s.text != null) buf.write(s.text);
    return true;
  });
  return buf.toString();
}

void main() {
  testWidgets('highlighted source stays byte-identical to the text',
      (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));

    final ctrl = SourceHighlightController(text: _md)
      ..theme = theme()
      ..highlightEnabled = true;
    final span = ctrl.buildTextSpan(
        context: ctx, style: theme().monoStyle, withComposing: false);
    expect(plain(span), _md);

    // A heading's text is bold; the fence body is span-styled code.
    final segments = <(String, TextStyle?)>[];
    span.visitChildren((s) {
      if (s is TextSpan && s.text != null) segments.add((s.text!, s.style));
      return true;
    });
    expect(
        segments.any((e) =>
            e.$1.contains('Title with') &&
            e.$2?.fontWeight == FontWeight.w700),
        isTrue);
    expect(segments.any((e) => e.$1 == 'void main() {}'), isTrue);

    // Disabled: one plain span, still identical.
    ctrl.highlightEnabled = false;
    final off = ctrl.buildTextSpan(
        context: ctx, style: theme().monoStyle, withComposing: false);
    expect(plain(off), _md);

    ctrl.dispose();
  });

  testWidgets('degenerate inputs keep the identity', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    for (final s in [
      '',
      '\n',
      '```\nunclosed fence',
      '| lonely pipe',
      '# ',
      '> ',
      '******',
      '=======',
      'a\n\n\n\nb\n',
    ]) {
      final ctrl = SourceHighlightController(text: s)..theme = theme();
      final span = ctrl.buildTextSpan(
          context: ctx, style: theme().monoStyle, withComposing: false);
      expect(plain(span), s, reason: 'input: ${s.replaceAll('\n', r'\n')}');
      ctrl.dispose();
    }
  });
}
