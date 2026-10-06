import Cocoa
import Darwin
import FlutterMacOS

/// Foundation owns sandbox-aware staging and replacement. Dart owns artifact
/// validation and flushes the completed bytes before requesting publication.
final class ArtifactFileChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "meow_chess/artifact_file", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      do {
        switch call.method {
        case "stagingDirectory":
          guard let path = call.arguments as? String, path.hasPrefix("/") else {
            result(FlutterError(code: "invalid-path", message: "Expected an absolute file path", details: nil))
            return
          }
          let directory = try replacementDirectory(for: URL(fileURLWithPath: path))
          result(directory.path)
        case "publish":
          guard let args = call.arguments as? [String: Any],
            let source = args["source"] as? String, let destination = args["destination"] as? String,
            source.hasPrefix("/"), destination.hasPrefix("/")
          else {
            result(FlutterError(code: "invalid-path", message: "Expected source and destination paths", details: nil))
            return
          }
          try publish(
            source: URL(fileURLWithPath: source), to: URL(fileURLWithPath: destination),
            replaceExisting: args["replaceExisting"] as? Bool ?? true)
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "artifact-save", message: error.localizedDescription, details: nil))
      }
    }
  }

  static func replacementDirectory(for destination: URL) throws -> URL {
    try FileManager.default.url(
      for: .itemReplacementDirectory, in: .userDomainMask,
      appropriateFor: destination, create: true)
  }

  static func publish(source: URL, to destination: URL, replaceExisting: Bool = true) throws {
    let manager = FileManager.default
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var publicationError: Error?
    coordinator.coordinate(writingItemAt: destination, options: .forReplacing, error: &coordinationError) { url in
      do {
        if replaceExisting && manager.fileExists(atPath: url.path) {
          _ = try manager.replaceItemAt(url, withItemAt: source)
        } else {
          // Enforce non-replacement in the filesystem operation itself, even
          // when a competing process creates the target during coordination.
          try moveExclusively(source, to: url)
        }
        // Fsync the published file itself, not its parent directory: the
        // sandbox grant from the save panel covers this exact path, but opening
        // the enclosing directory as its own resource is denied with EPERM even
        // for a user-selected destination.
        try fsyncPublished(url)
      } catch {
        publicationError = error
      }
    }
    if let error = coordinationError { throw error }
    if let error = publicationError { throw error }
  }

  private static func fsyncPublished(_ url: URL) throws {
    let descriptor = url.withUnsafeFileSystemRepresentation { path in
      path.map { Darwin.open($0, O_RDONLY) } ?? -1
    }
    guard descriptor >= 0 else { throw posixError(url, stage: "open-published") }
    defer { _ = Darwin.close(descriptor) }
    var status: Int32
    repeat { status = Darwin.fsync(descriptor) } while status != 0 && errno == EINTR
    guard status == 0 else { throw posixError(url, stage: "fsync-published") }
  }

  private static func posixError(_ url: URL, stage: String) -> NSError {
    NSError(
      domain: NSPOSIXErrorDomain, code: Int(errno),
      userInfo: [
        NSFilePathErrorKey: url.path,
        NSLocalizedDescriptionKey:
          "[\(stage)] \(String(cString: strerror(errno))) (errno \(errno)) at \(url.path)",
      ])
  }

  private static func moveExclusively(_ source: URL, to destination: URL) throws {
    // renamex_np(RENAME_EXCL) is denied with EPERM under App Sandbox, which
    // does not recognize this flagged rename variant. link()+unlink() gives
    // the same atomic "fail if destination exists" guarantee via syscalls the
    // sandbox profile does allow for granted paths.
    let linkStatus = source.withUnsafeFileSystemRepresentation { from in
      destination.withUnsafeFileSystemRepresentation { to -> Int32 in
        guard let from = from, let to = to else { errno = EINVAL; return -1 }
        return Darwin.link(from, to)
      }
    }
    guard linkStatus == 0 else { throw posixError(destination, stage: "link") }
    let unlinkStatus = source.withUnsafeFileSystemRepresentation { from in
      from.map { Darwin.unlink($0) } ?? -1
    }
    guard unlinkStatus == 0 else { throw posixError(source, stage: "unlink-source") }
  }
}
