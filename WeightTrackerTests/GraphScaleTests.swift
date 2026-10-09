import CoreGraphics
import XCTest
@testable import WeightTracker

final class GraphScaleTests: XCTestCase {
    func testSinglePointScaleAddsTimeAndWeightPadding() {
        let entry = WeightEntry(weightLbs: 185, recordedAt: Date(timeIntervalSinceReferenceDate: 1_000))

        let scale = GraphScale(entries: [entry])

        XCTAssertLessThan(scale.timeLower, entry.recordedAt)
        XCTAssertGreaterThan(scale.timeUpper, entry.recordedAt)
        XCTAssertLessThan(scale.weightLower, entry.weightLbs)
        XCTAssertGreaterThan(scale.weightUpper, entry.weightLbs)
    }

    func testMultiplePointScaleContainsAllEntries() {
        let entries = [
            WeightEntry(weightLbs: 190, recordedAt: Date(timeIntervalSinceReferenceDate: 1_000)),
            WeightEntry(weightLbs: 182, recordedAt: Date(timeIntervalSinceReferenceDate: 10_000)),
            WeightEntry(weightLbs: 188, recordedAt: Date(timeIntervalSinceReferenceDate: 20_000))
        ]

        let scale = GraphScale(entries: entries)

        XCTAssertLessThan(scale.timeLower, entries[0].recordedAt)
        XCTAssertGreaterThan(scale.timeUpper, entries[2].recordedAt)
        XCTAssertLessThan(scale.weightLower, 182)
        XCTAssertGreaterThan(scale.weightUpper, 190)
    }

    func testSameWeightPointsStillHaveVerticalRange() {
        let entries = [
            WeightEntry(weightLbs: 175, recordedAt: Date(timeIntervalSinceReferenceDate: 1_000)),
            WeightEntry(weightLbs: 175, recordedAt: Date(timeIntervalSinceReferenceDate: 2_000))
        ]

        let scale = GraphScale(entries: entries)

        XCTAssertGreaterThan(scale.weightUpper - scale.weightLower, 0)
        XCTAssertLessThan(scale.weightLower, 175)
        XCTAssertGreaterThan(scale.weightUpper, 175)
    }

    func testWideTimeRangeMapsEarlierEntryLeftOfLaterEntry() {
        let early = WeightEntry(weightLbs: 210, recordedAt: Date(timeIntervalSinceReferenceDate: 1_000))
        let late = WeightEntry(weightLbs: 200, recordedAt: Date(timeIntervalSinceReferenceDate: 1_000_000))
        let scale = GraphScale(entries: [late, early])
        let rect = CGRect(x: 0, y: 0, width: 600, height: 300)

        XCTAssertLessThan(scale.point(for: early, in: rect).x, scale.point(for: late, in: rect).x)
    }

    func testVisibleTimeRangeZoomsHorizontalScale() {
        let earlyDate = Date(timeIntervalSinceReferenceDate: 1_000)
        let lateDate = earlyDate.addingTimeInterval(10 * 24 * 60 * 60)
        let early = WeightEntry(weightLbs: 210, recordedAt: earlyDate)
        let late = WeightEntry(weightLbs: 200, recordedAt: lateDate)
        let scale = GraphScale(
            entries: [early, late],
            visibleTimeLower: earlyDate,
            visibleTimeUpper: earlyDate.addingTimeInterval(5 * 24 * 60 * 60)
        )
        let rect = CGRect(x: 10, y: 0, width: 500, height: 300)

        XCTAssertEqual(scale.point(for: early, in: rect).x, rect.minX, accuracy: 0.001)
        XCTAssertGreaterThan(scale.point(for: late, in: rect).x, rect.maxX)
    }

    func testScaleIncludesGoalProjectionRange() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let projection = WeightGoalProjection(startDate: now)

        let scale = GraphScale(entries: [], projectionPoints: projection.points)

        XCTAssertLessThan(scale.timeLower, now)
        XCTAssertGreaterThan(scale.timeUpper, projection.targetDate)
        XCTAssertLessThan(scale.weightLower, 150)
        XCTAssertGreaterThan(scale.weightUpper, 167.4)
    }

    func testGoalProjectionUsesOnePoundPerWeekToReachTarget() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let projection = WeightGoalProjection(startDate: now)
        let expectedTarget = now.addingTimeInterval(17.4 * 7 * 24 * 60 * 60)

        XCTAssertEqual(projection.currentWeightLbs, 167.4, accuracy: 0.001)
        XCTAssertEqual(projection.targetWeightLbs, 150, accuracy: 0.001)
        XCTAssertEqual(projection.targetDate.timeIntervalSince(expectedTarget), 0, accuracy: 0.001)
    }

    func testGoalProjectionExtendsBeforeStartDate() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let projection = WeightGoalProjection(startDate: now)
        let oneWeekEarlier = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let projectedPoint = projection.point(at: oneWeekEarlier)

        XCTAssertEqual(projectedPoint.recordedAt, oneWeekEarlier)
        XCTAssertEqual(projectedPoint.weightLbs, 168.4, accuracy: 0.001)
    }

    func testHitTestingSelectsNearestNodeWithinRadius() {
        let first = WeightEntry(weightLbs: 210, recordedAt: Date(timeIntervalSinceReferenceDate: 1_000))
        let second = WeightEntry(weightLbs: 205, recordedAt: Date(timeIntervalSinceReferenceDate: 2_000))
        let entries = [first, second]
        let scale = GraphScale(entries: entries)
        let rect = CGRect(x: 0, y: 0, width: 300, height: 200)
        let secondPoint = scale.point(for: second, in: rect)
        let tester = GraphHitTester(entries: entries, scale: scale, rect: rect, hitRadius: 24)

        XCTAssertEqual(tester.entry(at: CGPoint(x: secondPoint.x + 3, y: secondPoint.y + 2)), second)
        XCTAssertNil(tester.entry(at: CGPoint(x: rect.maxX + 100, y: rect.maxY + 100)))
    }

    func testTimeWindowZoomsInAndClampsZoomOutToFullRange() {
        let fullLower = Date(timeIntervalSinceReferenceDate: 1_000)
        let fullUpper = Date(timeIntervalSinceReferenceDate: 65_000)
        let window = GraphTimeWindow(fullLower: fullLower, fullUpper: fullUpper)

        let zoomed = window.zoomed(by: 2, anchorRatio: 0.5)
        XCTAssertEqual(zoomed.visibleDuration, window.fullDuration / 2, accuracy: 0.001)
        XCTAssertGreaterThan(zoomed.visibleLower, fullLower)
        XCTAssertLessThan(zoomed.visibleUpper, fullUpper)

        let zoomedOut = zoomed.zoomed(by: 0.01, anchorRatio: 0.5)
        XCTAssertEqual(zoomedOut.visibleLower.timeIntervalSince(fullLower), 0, accuracy: 0.001)
        XCTAssertEqual(zoomedOut.visibleUpper.timeIntervalSince(fullUpper), 0, accuracy: 0.001)
    }

    func testTimeWindowAllowsSubDayZoomForLongRanges() {
        let fullLower = Date(timeIntervalSinceReferenceDate: 1_000)
        let fullUpper = fullLower.addingTimeInterval(128 * 24 * 60 * 60)
        let window = GraphTimeWindow(fullLower: fullLower, fullUpper: fullUpper)

        let zoomed = window.zoomed(by: 10_000, anchorRatio: 0.5)

        XCTAssertEqual(zoomed.visibleDuration, 12 * 60 * 60, accuracy: 0.001)
    }

    func testTimeWindowPanStaysInsideFullRange() {
        let fullLower = Date(timeIntervalSinceReferenceDate: 1_000)
        let fullUpper = Date(timeIntervalSinceReferenceDate: 65_000)
        let window = GraphTimeWindow(fullLower: fullLower, fullUpper: fullUpper)
            .zoomed(by: 4, anchorRatio: 0.5)

        let pannedRight = window.panned(byXTranslation: 5_000, plotWidth: 500)
        XCTAssertEqual(pannedRight.visibleLower.timeIntervalSince(fullLower), 0, accuracy: 0.001)

        let pannedLeft = window.panned(byXTranslation: -5_000, plotWidth: 500)
        XCTAssertEqual(pannedLeft.visibleUpper.timeIntervalSince(fullUpper), 0, accuracy: 0.001)
    }
}
