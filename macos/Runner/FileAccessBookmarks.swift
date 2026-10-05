import Cocoa
import FlutterMacOS

/// Device-local access grants, independent of portable event data and history.
/// The platform channel and Finder callbacks both use this store on the main thread.
final class FileAccessBookmarks {
  static let shared = FileAccessBookmarks()
  static let preferenceKey = "meow.securityScopedBookmarks.v1"

  private let defaults: UserDefaults
  private var scopedURLs: [String: URL] = [:]
  private var terminationObserver: NSObjectProtocol?

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    terminationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.releaseAccess()
    }
  }

  deinit {
    if let observer = terminationObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    releaseAccess()
  }

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "meow_chess/file_access", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "restore":
        result(shared.restore())
      case "remember":
        guard let path = call.arguments as? String, path.hasPrefix("/") else {
          result(FlutterError(
            code: "invalid-path", message: "Expected an absolute file path", details: nil))
          return
        }
        do {
          try shared.remember(URL(fileURLWithPath: path))
          result(nil)
        } catch {
          result(FlutterError(
            code: "file-access", message: error.localizedDescription, details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Remember selected files and folders while the current user grant is valid.
  /// Finder's original URL is retained even if persisting its bookmark fails.
  func remember(_ url: URL) throws {
    retainAccess(to: url)
    let data = try bookmark(for: url)
    // A URL rebuilt from a Dart path has no security-scope information. Resolve
    // the new bookmark and retain that scoped URL for subsequent SQLite/backups.
    var stale = false
    retainAccess(to: try resolve(data, stale: &stale))
    var bookmarks = defaults.dictionary(forKey: Self.preferenceKey) ?? [:]
    bookmarks[url.standardizedFileURL.path] = data
    defaults.set(bookmarks, forKey: Self.preferenceKey)
  }

  /// Failed entries remain available for retry after a disconnected disk returns.
  /// Never mount disks or prompt during startup, and do not abandon other grants.
  func restore() -> [String] {
    var bookmarks = defaults.dictionary(forKey: Self.preferenceKey) ?? [:]
    var failures: [String] = []
    var changed = false
    for path in bookmarks.keys.sorted() {
      do {
        guard let data = bookmarks[path] as? Data else {
          failures.append(path)
          continue
        }
        var stale = false
        let url = try resolve(data, stale: &stale)
        retainAccess(to: url)
        guard try url.checkResourceIsReachable() else {
          failures.append(path)
          continue
        }
        if stale {
          bookmarks[path] = try bookmark(for: url)
          changed = true
        }
      } catch {
        failures.append(path)
      }
    }
    if changed { defaults.set(bookmarks, forKey: Self.preferenceKey) }
    return failures
  }

  /// Every successful start is paired once, including repeated restore calls.
  func releaseAccess() {
    let urls = Array(scopedURLs.values)
    scopedURLs.removeAll()
    for url in urls { url.stopAccessingSecurityScopedResource() }
  }

  private func retainAccess(to url: URL) {
    let path = url.standardizedFileURL.path
    if scopedURLs[path] == nil && url.startAccessingSecurityScopedResource() {
      scopedURLs[path] = url
    }
  }

  private func bookmark(for url: URL) throws -> Data {
    try url.bookmarkData(
      options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
  }

  private func resolve(_ data: Data, stale: inout Bool) throws -> URL {
    try URL(
      resolvingBookmarkData: data,
      options: [.withSecurityScope, .withoutUI, .withoutMounting],
      relativeTo: nil, bookmarkDataIsStale: &stale)
  }
}
