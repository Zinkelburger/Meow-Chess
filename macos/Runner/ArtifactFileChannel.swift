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
        // Opening for metadata avoids asking to read the selected file's
        // siblings. Acquire before publication so failure leaves the old file.
        let parent = url.deletingLastPathComponent()
        let descriptor = parent.withUnsafeFileSystemRepresentation { path in
          path.map { Darwin.open($0, O_EVTONLY | O_DIRECTORY) } ?? -1
        }
        guard descriptor >= 0 else { throw posixError(parent) }
        defer { _ = Darwin.close(descriptor) }
        if replaceExisting && manager.fileExists(atPath: url.path) {
          _ = try manager.replaceItemAt(url, withItemAt: source)
        } else {
          // Enforce non-replacement in the filesystem operation itself, even
          // when a competing process creates the target during coordination.
          try moveExclusively(source, to: url)
        }
        var status: Int32
        repeat { status = Darwin.fsync(descriptor) } while status != 0 && errno == EINTR
        guard status == 0 else { throw posixError(parent) }
      } catch {
        publicationError = error
      }
    }
    if let error = coordinationError { throw error }
    if let error = publicationError { throw error }
  }

  private static func posixError(_ url: URL) -> NSError {
    NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path])
  }

  private static func moveExclusively(_ source: URL, to destination: URL) throws {
    let status = source.withUnsafeFileSystemRepresentation { from in
      destination.withUnsafeFileSystemRepresentation { to -> Int32 in
        guard let from = from, let to = to else { errno = EINVAL; return -1 }
        return Darwin.renamex_np(from, to, UInt32(RENAME_EXCL))
      }
    }
    guard status == 0 else { throw posixError(destination) }
  }
}
