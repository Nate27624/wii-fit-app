import XCTest
@testable import WeightTracker

@MainActor
final class WeightStoreTests: XCTestCase {
    func testAddingEntryPersistsWeightAndTimestamp() throws {
        let fileURL = try temporaryFileURL()
        let store = WeightStore(fileURL: fileURL)
        let date = Date(timeIntervalSinceReferenceDate: 800)

        store.add(weightLbs: 181.4, recordedAt: date)

        let reloaded = WeightStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.entries, [WeightEntry(id: reloaded.entries[0].id, weightLbs: 181.4, recordedAt: date)])
        XCTAssertEqual(reloaded.entries[0].weightLbs, 181.4)
        XCTAssertEqual(reloaded.entries[0].recordedAt, date)
    }

    func testDeletingEntryRemovesOnlySelectedRecord() throws {
        let fileURL = try temporaryFileURL()
        let store = WeightStore(fileURL: fileURL)
        store.add(weightLbs: 180, recordedAt: Date(timeIntervalSinceReferenceDate: 100))
        store.add(weightLbs: 181, recordedAt: Date(timeIntervalSinceReferenceDate: 200))

        let deletedID = store.entries[0].id
        store.delete(id: deletedID)

        XCTAssertEqual(store.entries.map(\.weightLbs), [181])
        XCTAssertFalse(store.entries.contains { $0.id == deletedID })

        let reloaded = WeightStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.entries.map(\.weightLbs), [181])
    }

    func testLoadHandlesEmptyFile() throws {
        let fileURL = try temporaryFileURL()
        try Data().write(to: fileURL)

        let store = WeightStore(fileURL: fileURL)

        XCTAssertTrue(store.entries.isEmpty)
    }

    func testLoadHandlesMalformedFile() throws {
        let fileURL = try temporaryFileURL()
        try Data("not json".utf8).write(to: fileURL)

        let store = WeightStore(fileURL: fileURL)

        XCTAssertTrue(store.entries.isEmpty)
    }

    private func temporaryFileURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("weights.json")
    }
}
