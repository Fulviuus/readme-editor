/// Native platforms: PNG bytes of the clipboard image, or null when the
/// clipboard has none (or the channel is unregistered on this platform).
library;

import 'package:flutter/services.dart';

const _channel = MethodChannel('readme/clipboard');

Future<Uint8List?> readClipboardImagePng() async {
  try {
    return await _channel.invokeMethod<Uint8List>('imagePng');
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}
