import Combine
import Foundation

@MainActor
final class WeightStore: ObservableObject {
    @Published private(set) var entries: [WeightEntry]

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL, entries: [WeightEntry] = []) {
        self.fileURL = fileURL
        self.entries = entries.sortedByTime()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        load()
    }

    static func live() -> WeightStore {
        let processInfo = ProcessInfo.processInfo
        let directory: URL

        if processInfo.isUITesting {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("WeightTrackerUITests", isDirectory: true)
        } else {
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("WeightTracker", isDirectory: true)
        }

        let fileURL = directory.appendingPathComponent("weights.json")
        if processInfo.arguments.contains("--reset-data") || processInfo.environment["RESET_DATA"] == "1" {
            try? FileManager.default.removeItem(at: fileURL)
        }

        return WeightStore(fileURL: fileURL)
    }

    func add(weightLbs: Double, recordedAt: Date = Date()) {
        entries.append(WeightEntry(weightLbs: weightLbs, recordedAt: recordedAt))
        entries = entries.sortedByTime()
        persist()
    }

    func delete(id: WeightEntry.ID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            entries = entries.sortedByTime()
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            guard !data.isEmpty else {
                entries = []
                return
            }
            entries = try decoder.decode([WeightEntry].self, from: data).sortedByTime()
        } catch {
            entries = []
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            assertionFailure("Failed to persist weights: \(error)")
        }
    }
}

private extension Array where Element == WeightEntry {
    func sortedByTime() -> [WeightEntry] {
        sorted { lhs, rhs in
            if lhs.recordedAt == rhs.recordedAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.recordedAt < rhs.recordedAt
        }
    }
}
