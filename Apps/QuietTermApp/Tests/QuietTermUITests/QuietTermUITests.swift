import XCTest

@MainActor
final class QuietTermUITests: XCTestCase {
    func testMockSSHPasswordFlowConnectsTerminal() {
        let app = XCUIApplication()
        app.launchEnvironment["QUIETTERM_UI_TEST_MOCK_SSH"] = "1"
        app.launchEnvironment["QUIETTERM_SSH_ALIAS"] = "UI Test Host"
        app.launchEnvironment["QUIETTERM_SSH_HOST"] = "ui-test.local"
        app.launchEnvironment["QUIETTERM_SSH_PORT"] = "22"
        app.launchEnvironment["QUIETTERM_SSH_USERNAME"] = "quiet"
        app.launch()

        let hostButton = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "UI Test Host")).firstMatch
        XCTAssertTrue(hostButton.waitForExistence(timeout: 5))
        hostButton.tap()

        let trustAlert = app.alerts["Trust Host Key?"]
        XCTAssertTrue(trustAlert.waitForExistence(timeout: 5))
        trustAlert.buttons["Trust"].tap()

        let passwordField = app.secureTextFields["quietterm.password.field"].firstMatch
        XCTAssertTrue(passwordField.waitForExistence(timeout: 8))
        passwordField.tap()
        passwordField.typeText("quiet-password")

        app.buttons["quietterm.password.connect"].tap()

        XCTAssertFalse(app.secureTextFields["quietterm.password.field"].exists)
        XCTAssertFalse(app.alerts["Trust Host Key?"].exists)
    }
}
