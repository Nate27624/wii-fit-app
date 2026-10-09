import XCTest

@MainActor
final class WeightTrackerUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false

        await MainActor.run {
            XCUIDevice.shared.orientation = .portrait

            app = XCUIApplication()
            app.launchArguments = ["--uitesting", "--reset-data"]
            app.launchEnvironment = ["UITESTING": "1", "RESET_DATA": "1"]
            app.launch()
        }
    }

    func testSubmitWeightAndTapNodeShowsDetails() {
        addWeight("184.6")

        XCTAssertTrue(app.staticTexts["Selected Entry"].waitForExistence(timeout: 2))
        tapSingleEntryNode()

        XCTAssertTrue(app.staticTexts["Selected Entry"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Weight"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Recorded"].waitForExistence(timeout: 2))
    }

    func testDeleteSelectedEntryRemovesItFromGraph() {
        addWeight("180.2")
        XCTAssertTrue(app.staticTexts["Selected Entry"].waitForExistence(timeout: 2))
        tapSingleEntryNode()

        app.buttons["Delete"].tap()

        XCTAssertFalse(app.staticTexts["Selected Entry"].waitForExistence(timeout: 1))
    }

    func testLandscapeRotationKeepsPortraitLayout() {
        XCUIDevice.shared.orientation = .landscapeLeft

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 2))
        XCTAssertGreaterThan(window.frame.height, window.frame.width)
    }

    func testTappingOutsideWeightInputDismissesKeyboard() {
        let input = app.textFields["weight-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 2))
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))

        app.descendants(matching: .any)["weight-graph"].firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            .tap()

        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1))
    }

    private func addWeight(_ value: String) {
        let input = app.textFields["weight-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 2))
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        input.typeText(value)
        app.buttons["submit-button"].tap()
    }

    private func tapSingleEntryNode() {
        let graph = app.descendants(matching: .any)["weight-graph"].firstMatch
        XCTAssertTrue(graph.waitForExistence(timeout: 2))
        graph.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
}
