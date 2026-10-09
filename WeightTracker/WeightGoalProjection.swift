import Foundation

struct ProjectedWeightPoint: Equatable {
    let weightLbs: Double
    let recordedAt: Date
}

struct WeightGoalProjection: Equatable {
    static let defaultCurrentWeightLbs = 167.4
    static let defaultTargetWeightLbs = 150.0
    static let defaultHealthyLossRateLbsPerWeek = 1.0

    let currentWeightLbs: Double
    let targetWeightLbs: Double
    let healthyLossRateLbsPerWeek: Double
    let startDate: Date
    let targetDate: Date

    init(
        currentWeightLbs: Double = Self.defaultCurrentWeightLbs,
        targetWeightLbs: Double = Self.defaultTargetWeightLbs,
        healthyLossRateLbsPerWeek: Double = Self.defaultHealthyLossRateLbsPerWeek,
        startDate: Date = Date()
    ) {
        self.currentWeightLbs = currentWeightLbs
        self.targetWeightLbs = targetWeightLbs
        self.healthyLossRateLbsPerWeek = healthyLossRateLbsPerWeek
        self.startDate = startDate

        let weeklyRate = max(healthyLossRateLbsPerWeek, 0.1)
        let poundsToLose = max(0, currentWeightLbs - targetWeightLbs)
        let weeksToTarget = poundsToLose / weeklyRate
        targetDate = startDate.addingTimeInterval(weeksToTarget * 7 * 24 * 60 * 60)
    }

    var points: [ProjectedWeightPoint] {
        [
            ProjectedWeightPoint(weightLbs: currentWeightLbs, recordedAt: startDate),
            ProjectedWeightPoint(weightLbs: targetWeightLbs, recordedAt: targetDate)
        ]
    }

    func point(at date: Date) -> ProjectedWeightPoint {
        let duration = max(targetDate.timeIntervalSince(startDate), 1)
        let progress = date.timeIntervalSince(startDate) / duration
        let weight = currentWeightLbs + (targetWeightLbs - currentWeightLbs) * progress

        return ProjectedWeightPoint(weightLbs: weight, recordedAt: date)
    }
}
