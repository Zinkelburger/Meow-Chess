import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // Finder hands over double-clicked .meow files here rather than on the
  // command line. They queue until Dart announces it is ready, the same
  // protocol as the Linux and Windows runners (meow_chess/file_open).
  private var fileChannel: FlutterMethodChannel?
  private var pendingFiles: [String] = []
  private var filesReady = false
  // Finder grants the sandboxed app access to the files it opens; keep those
  // grants for the life of the process.
  private var scopedFiles: [URL] = []

  func attachFileOpenChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "meow_chess/file_open", binaryMessenger: messenger)
    fileChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      if call.method == "reveal" {
        guard let path = call.arguments as? String, !path.isEmpty else {
          result(FlutterError(code: "invalid_path", message: "A file path is required.", details: nil))
          return
        }
        guard FileManager.default.fileExists(atPath: path) else {
          result(FlutterError(code: "reveal_failed", message: "The file could not be found.", details: nil))
          return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        result(nil)
        return
      }
      guard call.method == "ready" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.filesReady = true
      let files = self.pendingFiles
      self.pendingFiles.removeAll()
      result(files)
    }
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    let files = urls.filter { $0.isFileURL }
    for url in files {
      if url.startAccessingSecurityScopedResource() { scopedFiles.append(url) }
    }
    let paths = files.map { $0.path }
    if !paths.isEmpty {
      if filesReady {
        fileChannel?.invokeMethod("open", arguments: paths)
      } else {
        pendingFiles.append(contentsOf: paths)
      }
      mainFlutterWindow?.makeKeyAndOrderFront(nil)
      application.activate(ignoringOtherApps: true)
    }
    let otherURLs = urls.filter { !$0.isFileURL }
    if !otherURLs.isEmpty { super.application(application, open: otherURLs) }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
