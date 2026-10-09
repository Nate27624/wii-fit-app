import Foundation

struct WeightEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let weightLbs: Double
    let recordedAt: Date

    init(id: UUID = UUID(), weightLbs: Double, recordedAt: Date = Date()) {
        self.id = id
        self.weightLbs = weightLbs
        self.recordedAt = recordedAt
    }
}
