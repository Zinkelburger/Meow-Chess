import Cocoa
import FlutterMacOS
import XCTest
@testable import Meow_Chess

class RunnerTests: XCTestCase {

  func testFileAndFolderBookmarksSurviveStoreRecreation() throws {
    let manager = FileManager.default
    let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: directory) }
    let file = directory.appendingPathComponent("Chess résumé.meow")
    try Data("event contents".utf8).write(to: file)
    let suite = "meow.bookmark-tests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let original = FileAccessBookmarks(defaults: defaults)
    try original.remember(file)
    try original.remember(directory)
    original.releaseAccess()

    let reopened = FileAccessBookmarks(defaults: defaults)
    defer { reopened.releaseAccess() }
    XCTAssertEqual(reopened.restore(), [])
    // Repeated restores must preserve access without unbalanced scope starts.
    XCTAssertEqual(reopened.restore(), [])
    XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "event contents")
    let backup = directory.appendingPathComponent("backup.meow")
    try Data("backup contents".utf8).write(to: backup)
    XCTAssertTrue(manager.fileExists(atPath: backup.path))
    let bookmarks = try XCTUnwrap(defaults.dictionary(forKey: FileAccessBookmarks.preferenceKey))
    XCTAssertEqual(bookmarks.count, 2)
    XCTAssertNotNil(bookmarks[file.standardizedFileURL.path] as? Data)
    XCTAssertNotNil(bookmarks[directory.standardizedFileURL.path] as? Data)
  }

  func testInvalidAndUnavailableBookmarksDoNotBlockOtherEntries() throws {
    let manager = FileManager.default
    let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: directory) }
    let file = directory.appendingPathComponent("available.meow")
    let missing = directory.appendingPathComponent("missing.meow")
    try Data("available".utf8).write(to: file)
    try Data("will disappear".utf8).write(to: missing)
    let suite = "meow.bookmark-tests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let original = FileAccessBookmarks(defaults: defaults)
    try original.remember(file)
    try original.remember(missing)
    original.releaseAccess()
    try manager.removeItem(at: missing)
    var entries = try XCTUnwrap(defaults.dictionary(forKey: FileAccessBookmarks.preferenceKey))
    entries["/invalid-bookmark"] = Data([0, 1, 2])
    entries["/invalid-value"] = "not bookmark data"
    defaults.set(entries, forKey: FileAccessBookmarks.preferenceKey)

    let reopened = FileAccessBookmarks(defaults: defaults)
    defer { reopened.releaseAccess() }
    XCTAssertEqual(Set(reopened.restore()), Set([
      "/invalid-bookmark", "/invalid-value", missing.standardizedFileURL.path,
    ]))
    XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "available")
    // Keep unavailable bookmarks for a later startup when a volume returns.
    XCTAssertEqual(defaults.dictionary(forKey: FileAccessBookmarks.preferenceKey)?.count, 4)
  }

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

  func testExclusivePublicationPreservesAFileThatAppearedDuringStaging() throws {
    let manager = FileManager.default
    let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: directory) }
    let source = directory.appendingPathComponent("staged.meow")
    let destination = directory.appendingPathComponent("event.meow")
    try Data("reviewed snapshot".utf8).write(to: source)
    try Data("another event".utf8).write(to: destination)
    XCTAssertThrowsError(try ArtifactFileChannel.publish(
      source: source, to: destination, replaceExisting: false))
    XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "another event")
    XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "reviewed snapshot")
  }

}
