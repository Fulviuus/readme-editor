import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // Preferences > General > "Quit when the window is closed".
    if UserDefaults.standard.object(forKey: "quitWhenClosed") == nil {
      return true
    }
    return UserDefaults.standard.bool(forKey: "quitWhenClosed")
  }

  override func applicationShouldHandleReopen(
      _ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      for window in sender.windows {
        window.makeKeyAndOrderFront(self)
      }
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
