import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerSpellChannel(flutterViewController)
    registerClipboardChannel(flutterViewController)

    super.awakeFromNib()
  }

  /// Clipboard image access (Flutter's Clipboard API is text-only).
  private func registerClipboardChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "readme/clipboard",
      binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "imagePng":
        let pasteboard = NSPasteboard.general
        if let png = pasteboard.data(forType: .png) {
          result(FlutterStandardTypedData(bytes: png))
          return
        }
        if let tiff = pasteboard.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
          result(FlutterStandardTypedData(bytes: png))
          return
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// System spell checker bridge. All range offsets are UTF-16 code units,
  /// which is also how Dart indexes strings — no conversion needed.
  private func registerSpellChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "readme/spell",
      binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      let checker = NSSpellChecker.shared
      let args = call.arguments as? [String: Any]
      switch call.method {
      case "check":
        guard let text = args?["text"] as? String else {
          result([[Int]]())
          return
        }
        let length = (text as NSString).length
        var ranges: [[Int]] = []
        var start = 0
        while start < length {
          let r = checker.checkSpelling(
            of: text, startingAt: start, language: nil, wrap: false,
            inSpellDocumentWithTag: 0, wordCount: nil)
          if r.location == NSNotFound || r.length == 0 { break }
          ranges.append([r.location, r.length])
          start = r.location + r.length
        }
        result(ranges)
      case "suggest":
        guard let word = args?["word"] as? String else {
          result([String]())
          return
        }
        let range = NSRange(location: 0, length: (word as NSString).length)
        let guesses = checker.guesses(
          forWordRange: range, in: word, language: nil,
          inSpellDocumentWithTag: 0)
        result(guesses ?? [String]())
      case "learn":
        if let word = args?["word"] as? String { checker.learnWord(word) }
        result(nil)
      case "ignore":
        if let word = args?["word"] as? String {
          checker.ignoreWord(word, inSpellDocumentWithTag: 0)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
