import CoreGraphics
import Foundation

struct GraphScale: Equatable {
    let timeLower: Date
    let timeUpper: Date
    let weightLower: Double
    let weightUpper: Double

    init(
        entries: [WeightEntry],
        projectionPoints: [ProjectedWeightPoint] = [],
        visibleTimeLower: Date? = nil,
        visibleTimeUpper: Date? = nil
    ) {
        let sorted = entries.sorted { $0.recordedAt < $1.recordedAt }
        let timeValues = sorted.map(\.recordedAt) + projectionPoints.map(\.recordedAt)
        let weightValues = sorted.map(\.weightLbs) + projectionPoints.map(\.weightLbs)
        let now = Date()

        guard let firstTime = timeValues.min(), let lastTime = timeValues.max() else {
            timeLower = now.addingTimeInterval(-3_600)
            timeUpper = now.addingTimeInterval(3_600)
            weightLower = 0
            weightUpper = 300
            return
        }

        let rawStart = firstTime.timeIntervalSinceReferenceDate
        let rawEnd = lastTime.timeIntervalSinceReferenceDate
        let rawDuration = max(rawEnd - rawStart, 60)
        let timePadding = max(rawDuration * 0.08, 60)
        let fullTimeLower = Date(timeIntervalSinceReferenceDate: rawStart - timePadding)
        let fullTimeUpper = Date(timeIntervalSinceReferenceDate: rawEnd + timePadding)
        let timeWindow = GraphTimeWindow(
            fullLower: fullTimeLower,
            fullUpper: fullTimeUpper,
            visibleLower: visibleTimeLower,
            visibleUpper: visibleTimeUpper
        )
        timeLower = timeWindow.visibleLower
        timeUpper = timeWindow.visibleUpper

        let minWeight = weightValues.min() ?? 0
        let maxWeight = weightValues.max() ?? 300
        let rawSpan = max(maxWeight - minWeight, 5)
        let weightPadding = max(rawSpan * 0.12, 2.5)
        weightLower = max(0, minWeight - weightPadding)
        weightUpper = maxWeight + weightPadding
    }

    func point(for entry: WeightEntry, in rect: CGRect) -> CGPoint {
        point(recordedAt: entry.recordedAt, weightLbs: entry.weightLbs, in: rect)
    }

    func point(for projectionPoint: ProjectedWeightPoint, in rect: CGRect) -> CGPoint {
        point(recordedAt: projectionPoint.recordedAt, weightLbs: projectionPoint.weightLbs, in: rect)
    }

    private func point(recordedAt: Date, weightLbs: Double, in rect: CGRect) -> CGPoint {
        let xRange = max(timeUpper.timeIntervalSince(timeLower), 1)
        let yRange = max(weightUpper - weightLower, 1)
        let xRatio = recordedAt.timeIntervalSince(timeLower) / xRange
        let yRatio = (weightLbs - weightLower) / yRange

        return CGPoint(
            x: rect.minX + rect.width * xRatio,
            y: rect.maxY - rect.height * yRatio
        )
    }

    func contains(date: Date) -> Bool {
        date >= timeLower && date <= timeUpper
    }
}

struct GraphTimeWindow: Equatable {
    let fullLower: Date
    let fullUpper: Date
    let visibleLower: Date
    let visibleUpper: Date

    init(fullLower: Date, fullUpper: Date, visibleLower: Date? = nil, visibleUpper: Date? = nil) {
        self.fullLower = fullLower
        self.fullUpper = max(fullUpper, fullLower.addingTimeInterval(1))

        let fullDuration = self.fullUpper.timeIntervalSince(fullLower)
        let minDuration = Self.minimumVisibleDuration(for: fullDuration)
        let requestedLower = visibleLower ?? fullLower
        let requestedUpper = visibleUpper ?? self.fullUpper
        let requestedDuration = max(requestedUpper.timeIntervalSince(requestedLower), minDuration)
        let visibleDuration = min(max(requestedDuration, minDuration), fullDuration)

        var lower = requestedLower
        if lower < fullLower {
            lower = fullLower
        }

        if lower.addingTimeInterval(visibleDuration) > self.fullUpper {
            lower = self.fullUpper.addingTimeInterval(-visibleDuration)
        }

        self.visibleLower = lower
        self.visibleUpper = lower.addingTimeInterval(visibleDuration)
    }

    var fullDuration: TimeInterval {
        fullUpper.timeIntervalSince(fullLower)
    }

    var visibleDuration: TimeInterval {
        visibleUpper.timeIntervalSince(visibleLower)
    }

    var isFullRange: Bool {
        abs(visibleLower.timeIntervalSince(fullLower)) < 0.5
            && abs(visibleUpper.timeIntervalSince(fullUpper)) < 0.5
    }

    func zoomed(by magnification: CGFloat, anchorRatio: CGFloat) -> GraphTimeWindow {
        let safeMagnification = max(TimeInterval(magnification), 0.05)
        let minDuration = Self.minimumVisibleDuration(for: fullDuration)
        let nextDuration = min(max(visibleDuration / safeMagnification, minDuration), fullDuration)
        let clampedAnchor = min(max(TimeInterval(anchorRatio), 0), 1)
        let anchorDate = visibleLower.addingTimeInterval(visibleDuration * clampedAnchor)
        let lower = anchorDate.addingTimeInterval(-nextDuration * clampedAnchor)

        return GraphTimeWindow(
            fullLower: fullLower,
            fullUpper: fullUpper,
            visibleLower: lower,
            visibleUpper: lower.addingTimeInterval(nextDuration)
        )
    }

    func panned(byXTranslation translation: CGFloat, plotWidth: CGFloat) -> GraphTimeWindow {
        guard plotWidth > 0 else { return self }

        let seconds = -TimeInterval(translation / plotWidth) * visibleDuration
        return GraphTimeWindow(
            fullLower: fullLower,
            fullUpper: fullUpper,
            visibleLower: visibleLower.addingTimeInterval(seconds),
            visibleUpper: visibleUpper.addingTimeInterval(seconds)
        )
    }

    private static func minimumVisibleDuration(for fullDuration: TimeInterval) -> TimeInterval {
        let sixHours: TimeInterval = 6 * 60 * 60
        return min(max(fullDuration / 256, sixHours), fullDuration)
    }
}

struct GraphHitTester {
    let entries: [WeightEntry]
    let scale: GraphScale
    let rect: CGRect
    let hitRadius: CGFloat

    func entry(at location: CGPoint) -> WeightEntry? {
        var nearestEntry: WeightEntry?
        var nearestDistance = CGFloat.greatestFiniteMagnitude

        for entry in entries {
            let point = scale.point(for: entry, in: rect)
            let distance = hypot(point.x - location.x, point.y - location.y)
            guard distance <= hitRadius, distance < nearestDistance else { continue }
            nearestEntry = entry
            nearestDistance = distance
        }

        return nearestEntry
    }
}
