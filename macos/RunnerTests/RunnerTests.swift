import Cocoa
import FlutterMacOS
import SQLite3
import XCTest
@testable import Meow_Chess

class RunnerTests: XCTestCase {

  // The shipped app is sandboxed, and the bookmark and publication paths differ
  // inside the sandbox. CI builds the test host unsigned, because GitHub's macOS
  // runners cannot launch the ad hoc signed, sandboxed host; the sandbox paths
  // are covered by running this scheme from Xcode, where this test asserts.
  func testHostRunsInsideTheAppSandbox() throws {
    try XCTSkipIf(
      ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil,
      "the test host is unsigned, so the App Sandbox is off; run from Xcode to cover it")
  }

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
    XCTAssertEqual(reopened.restore(), ["/invalid-bookmark"])
    XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "available")
    // A file deleted from a disk that is present is forgotten, as is an entry
    // that is not bookmark data; a bookmark that cannot be read is kept, like
    // one on a disk that is unplugged, for a later startup.
    let remaining = try XCTUnwrap(defaults.dictionary(forKey: FileAccessBookmarks.preferenceKey))
    XCTAssertEqual(Set(remaining.keys), Set([file.standardizedFileURL.path, "/invalid-bookmark"]))
    XCTAssertEqual(reopened.restore(), ["/invalid-bookmark"])
  }

  func testMovedFileBookmarkFollowsTheFile() throws {
    let manager = FileManager.default
    let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: directory) }
    let file = directory.appendingPathComponent("before.meow")
    let moved = directory.appendingPathComponent("after.meow")
    try Data("moved".utf8).write(to: file)
    let suite = "meow.bookmark-tests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let original = FileAccessBookmarks(defaults: defaults)
    try original.remember(file)
    original.releaseAccess()
    try manager.moveItem(at: file, to: moved)

    let reopened = FileAccessBookmarks(defaults: defaults)
    defer { reopened.releaseAccess() }
    XCTAssertEqual(reopened.restore(), [])
    let bookmarks = try XCTUnwrap(defaults.dictionary(forKey: FileAccessBookmarks.preferenceKey))
    // Compared without symlinks: a resolved URL may come back as /private/var.
    XCTAssertEqual(
      bookmarks.keys.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path },
      [moved.resolvingSymlinksInPath().path])
    XCTAssertEqual(reopened.restore(), [])
    XCTAssertEqual(try String(contentsOf: moved, encoding: .utf8), "moved")
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

  // The sandbox extends a chosen event's grant to SQLite's journal only for
  // extensions the app declares as related items.
  func testInfoPlistDeclaresTheJournalFilesAsRelatedItems() throws {
    let types = try XCTUnwrap(
      Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]])
    let related = types.filter { $0["NSIsRelatedItemType"] as? Bool == true }
    XCTAssertEqual(related.count, 1)
    let extensions = try XCTUnwrap(related.first?["CFBundleTypeExtensions"] as? [String])
    XCTAssertEqual(
      Set(extensions),
      Set(SQLiteSidecarPresenter.suffixes.map { SQLiteSidecarPresenter.eventExtension + $0 }))
  }

  func testEventFilesPresentTheirJournalsUntilAccessIsReleased() throws {
    let manager = FileManager.default
    let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: directory) }
    let event = directory.appendingPathComponent("Chess résumé.meow")
    let report = directory.appendingPathComponent("report.csv")
    try Data().write(to: event)
    try Data("report".utf8).write(to: report)
    let suite = "meow.bookmark-tests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    func canonical(_ url: URL?) -> String? { url?.resolvingSymlinksInPath().path }
    func presented() -> [SQLiteSidecarPresenter] {
      NSFileCoordinator.filePresenters.compactMap { $0 as? SQLiteSidecarPresenter }
        .filter { canonical($0.primaryPresentedItemURL)?.hasPrefix(canonical(directory)!) == true }
    }

    let store = FileAccessBookmarks(defaults: defaults)
    try store.remember(event)
    try store.remember(directory)
    try store.remember(report)
    // One presenter per journal suffix, all for the event; remembering the
    // same file again (as the resolved bookmark does) adds none.
    let sidecars = presented()
    XCTAssertEqual(sidecars.count, SQLiteSidecarPresenter.suffixes.count)
    XCTAssertEqual(
      Set(sidecars.compactMap { canonical($0.presentedItemURL) }),
      Set(SQLiteSidecarPresenter.suffixes.map { canonical(event)! + $0 }))
    XCTAssertEqual(Set(sidecars.compactMap { canonical($0.primaryPresentedItemURL) }), [canonical(event)!])
    store.releaseAccess()
    XCTAssertEqual(presented().count, 0)

    // Recent events are presented again from their bookmarks at startup.
    let reopened = FileAccessBookmarks(defaults: defaults)
    defer { reopened.releaseAccess() }
    XCTAssertEqual(reopened.restore(), [])
    XCTAssertEqual(presented().count, SQLiteSidecarPresenter.suffixes.count)
  }

  // Inside the test container every path is writable, so this cannot show the
  // sandbox grant itself; it shows SQLite keeps its write-ahead log beside a
  // presented event, in the locking mode the app uses, with presenters live.
  func testSQLiteWritesItsLogBesideAPresentedEvent() throws {
    let manager = FileManager.default
    let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: directory) }
    let event = directory.appendingPathComponent("club.meow")
    try Data().write(to: event)  // An empty file is an empty SQLite database.
    let suite = "meow.bookmark-tests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = FileAccessBookmarks(defaults: defaults)
    defer { store.releaseAccess() }
    try store.remember(event)

    var db: OpaquePointer?
    XCTAssertEqual(sqlite3_open(event.path, &db), SQLITE_OK)
    defer { sqlite3_close(db) }
    func text(_ sql: String) -> String? {
      var statement: OpaquePointer?
      guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
      defer { sqlite3_finalize(statement) }
      guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0)
      else { return nil }
      return String(cString: value)
    }
    XCTAssertEqual(text("PRAGMA locking_mode = EXCLUSIVE"), "exclusive")
    XCTAssertEqual(text("PRAGMA journal_mode = WAL"), "wal")
    XCTAssertEqual(sqlite3_exec(db, "CREATE TABLE t(x); INSERT INTO t VALUES(1)", nil, nil, nil), SQLITE_OK)
    XCTAssertTrue(manager.fileExists(atPath: event.path + "-wal"))
    XCTAssertEqual(text("SELECT count(*) FROM t"), "1")
  }

}
