import XCTest

final class AppConfigurationTests: XCTestCase {
    func testAppSupportsPortraitOnlyOrientation() throws {
        let testBundleURL = Bundle(for: Self.self).bundleURL
        let appBundleURL = testBundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let infoPlistURL = appBundleURL.appendingPathComponent("Info.plist")
        let infoDictionary = try XCTUnwrap(NSDictionary(contentsOf: infoPlistURL) as? [String: Any])
        let orientations = try XCTUnwrap(
            infoDictionary["UISupportedInterfaceOrientations"] as? [String]
        )
        let iPadOrientations = try XCTUnwrap(
            infoDictionary["UISupportedInterfaceOrientations~ipad"] as? [String]
        )

        XCTAssertEqual(Set(orientations), [
            "UIInterfaceOrientationPortrait"
        ])
        XCTAssertEqual(Set(iPadOrientations), Set(orientations))
        XCTAssertFalse(orientations.contains("UIInterfaceOrientationLandscapeLeft"))
        XCTAssertFalse(orientations.contains("UIInterfaceOrientationLandscapeRight"))
        XCTAssertEqual(infoDictionary["UIRequiresFullScreen"] as? Bool, true)
    }
}
