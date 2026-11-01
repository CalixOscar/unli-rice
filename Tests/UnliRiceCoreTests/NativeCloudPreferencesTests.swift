import XCTest
@testable import UnliRiceCore
final class NativeCloudPreferencesTests: XCTestCase {
    func testLegacyAndSavedChoice() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = dir.appendingPathComponent("events.jsonl")
        XCTAssertEqual(try NativeSyncPreferences.load(besideEventLog: log, legacyFolderChosen: false).mode, .privateDevice)
        XCTAssertEqual(try NativeSyncPreferences.load(besideEventLog: log, legacyFolderChosen: true).mode, .folder)
        try NativeSyncPreferences(mode: .iCloud).save(besideEventLog: log)
        XCTAssertEqual(try NativeSyncPreferences.load(besideEventLog: log, legacyFolderChosen: false).mode, .iCloud)
        try Data("bad".utf8).write(to: dir.appendingPathComponent("native-sync-preferences.json"))
        XCTAssertThrowsError(try NativeSyncPreferences.load(besideEventLog: log, legacyFolderChosen: false))
    }
}
