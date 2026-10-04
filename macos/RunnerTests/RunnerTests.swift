import Cocoa
import FlutterMacOS
import XCTest
@testable import Meow_Chess

class RunnerTests: XCTestCase {

  func testNativeArtifactCreationAndReplacement() throws {
    let manager = FileManager.default
    let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: directory) }
    let destination = directory.appendingPathComponent("Chess résumé.csv")
    for text in ["first complete report", "replacement report"] {
      let staging = try ArtifactFileChannel.replacementDirectory(for: destination)
      defer { try? manager.removeItem(at: staging) }
      let source = staging.appendingPathComponent("complete")
      try Data(text.utf8).write(to: source)
      try ArtifactFileChannel.publish(source: source, to: destination)
      XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), text)
      XCTAssertFalse(manager.fileExists(atPath: source.path))
    }
    XCTAssertEqual(try manager.contentsOfDirectory(atPath: directory.path), [destination.lastPathComponent])
  }

  func testMissingStagedFileCannotDestroyPreviousReport() throws {
    let manager = FileManager.default
    let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: directory) }
    let destination = directory.appendingPathComponent("report.csv")
    try Data("previous report".utf8).write(to: destination)
    XCTAssertThrowsError(try ArtifactFileChannel.publish(
      source: directory.appendingPathComponent("missing"), to: destination))
    XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "previous report")
  }

}
