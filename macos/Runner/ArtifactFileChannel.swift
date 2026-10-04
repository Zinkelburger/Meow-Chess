import Cocoa
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
          guard let args = call.arguments as? [String: String],
            let source = args["source"], let destination = args["destination"],
            source.hasPrefix("/"), destination.hasPrefix("/")
          else {
            result(FlutterError(code: "invalid-path", message: "Expected source and destination paths", details: nil))
            return
          }
          try publish(source: URL(fileURLWithPath: source), to: URL(fileURLWithPath: destination))
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

  static func publish(source: URL, to destination: URL) throws {
    let manager = FileManager.default
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var publicationError: Error?
    coordinator.coordinate(writingItemAt: destination, options: .forReplacing, error: &coordinationError) { url in
      do {
        if manager.fileExists(atPath: url.path) {
          _ = try manager.replaceItemAt(url, withItemAt: source)
        } else {
          try manager.moveItem(at: source, to: url)
        }
      } catch {
        publicationError = error
      }
    }
    if let error = coordinationError { throw error }
    if let error = publicationError { throw error }
  }
}
