import XCTest

@MainActor
final class QuietTermUITests: XCTestCase {
    func testMockSSHPasswordFlowConnectsTerminal() {
        let app = launchMockApp()
        connectMockHost(in: app)

        XCTAssertFalse(app.secureTextFields["quietterm.password.field"].exists)
        XCTAssertFalse(app.alerts["Trust Host Key?"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["quietterm.terminal"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["quietterm.session.state"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForSessionState(in: app, containing: "Connected"))
    }

    func testMockSSHCancelPasswordKeepsTabWithRetryActions() {
        let app = launchMockApp()
        openMockHost(in: app)
        trustHostKey(in: app)

        let passwordField = app.secureTextFields["quietterm.password.field"].firstMatch
        XCTAssertTrue(passwordField.waitForExistence(timeout: 8))
        app.buttons["Cancel"].tap()

        XCTAssertFalse(passwordField.exists)
        XCTAssertTrue(app.buttons["quietterm.session.retry"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quietterm.session.new"].exists)
        XCTAssertTrue(waitForSessionState(in: app, containing: "Authentication cancelled."))
        XCTAssertEqual(app.buttons.matching(identifier: "quietterm.session.tab").count, 1)
    }

    func testMockSSHDisconnectRetryReusesSameTab() {
        let app = launchMockApp(disconnectOnFirstConnect: true)
        connectMockHost(in: app)

        XCTAssertTrue(waitForSessionState(in: app, containing: "UI test forced disconnect."))
        XCTAssertTrue(app.buttons["quietterm.session.retry"].waitForExistence(timeout: 5))
        let initialTabCount = app.buttons.matching(identifier: "quietterm.session.tab").count
        XCTAssertEqual(initialTabCount, 1)

        app.buttons["quietterm.session.retry"].tap()
        XCTAssertFalse(app.alerts["Trust Host Key?"].waitForExistence(timeout: 1))

        let retryPasswordField = app.secureTextFields["quietterm.password.field"].firstMatch
        XCTAssertTrue(retryPasswordField.waitForExistence(timeout: 8))
        retryPasswordField.tap()
        retryPasswordField.typeText("retry-password")
        app.buttons["quietterm.password.connect"].tap()

        XCTAssertTrue(waitForSessionState(in: app, containing: "Connected"))
        XCTAssertEqual(app.buttons.matching(identifier: "quietterm.session.tab").count, initialTabCount)
        XCTAssertTrue(app.descendants(matching: .any)["quietterm.terminal"].waitForExistence(timeout: 5))
    }

    func testMockSSHTabIsolationAndCloseKeepsActiveTabConnected() {
        let app = launchMockApp(disconnectOnFirstConnect: true)
        connectMockHost(in: app)

        XCTAssertTrue(waitForSessionState(in: app, containing: "UI test forced disconnect."))
        XCTAssertTrue(app.buttons["quietterm.session.new"].waitForExistence(timeout: 5))
        app.buttons["quietterm.session.new"].tap()

        let secondPasswordField = app.secureTextFields["quietterm.password.field"].firstMatch
        XCTAssertTrue(secondPasswordField.waitForExistence(timeout: 8))
        secondPasswordField.tap()
        secondPasswordField.typeText("second-password")
        app.buttons["quietterm.password.connect"].tap()

        XCTAssertTrue(waitForSessionState(in: app, containing: "Connected"))
        XCTAssertTrue(
            waitForElementCount(
                app.buttons.matching(identifier: "quietterm.session.tab"),
                expectedCount: 2
            )
        )
        XCTAssertTrue(
            waitForElementCount(
                app.buttons.matching(identifier: "quietterm.session.close"),
                expectedCount: 2
            )
        )

        app.buttons.matching(identifier: "quietterm.session.close").element(boundBy: 0).tap()

        XCTAssertTrue(
            waitForElementCount(
                app.buttons.matching(identifier: "quietterm.session.tab"),
                expectedCount: 1
            )
        )
        XCTAssertTrue(
            waitForElementCount(
                app.buttons.matching(identifier: "quietterm.session.close"),
                expectedCount: 1
            )
        )
        XCTAssertTrue(waitForSessionState(in: app, containing: "Connected"))
        XCTAssertFalse(app.buttons["quietterm.session.retry"].exists)
    }

    func testMockSSHBackgroundResumeKeepsConnectedState() {
        let app = launchMockApp()
        connectMockHost(in: app)
        XCTAssertTrue(waitForSessionState(in: app, containing: "Connected"))

        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()

        XCTAssertTrue(waitForSessionState(in: app, containing: "Connected"))
    }

    private func launchMockApp(disconnectOnFirstConnect: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["QUIETTERM_UI_TEST_MOCK_SSH"] = "1"
        app.launchEnvironment["QUIETTERM_SSH_ALIAS"] = "UI Test Host"
        app.launchEnvironment["QUIETTERM_SSH_HOST"] = "ui-test.local"
        app.launchEnvironment["QUIETTERM_SSH_PORT"] = "22"
        app.launchEnvironment["QUIETTERM_SSH_USERNAME"] = "quiet"
        if disconnectOnFirstConnect {
            app.launchEnvironment["QUIETTERM_UI_TEST_DISCONNECT_ON_FIRST_CONNECT"] = "1"
        }
        app.launch()
        return app
    }

    private func connectMockHost(in app: XCUIApplication) {
        openMockHost(in: app)
        trustHostKey(in: app)

        let passwordField = app.secureTextFields["quietterm.password.field"].firstMatch
        XCTAssertTrue(passwordField.waitForExistence(timeout: 8))
        passwordField.tap()
        passwordField.typeText("quiet-password")
        app.buttons["quietterm.password.connect"].tap()
    }

    private func openMockHost(in app: XCUIApplication) {
        let hostButton = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "UI Test Host")).firstMatch
        XCTAssertTrue(hostButton.waitForExistence(timeout: 5))
        hostButton.tap()
    }

    private func trustHostKey(in app: XCUIApplication) {
        let trustAlert = app.alerts["Trust Host Key?"]
        XCTAssertTrue(trustAlert.waitForExistence(timeout: 5))
        trustAlert.buttons["Trust"].tap()
    }

    private func waitForSessionState(
        in app: XCUIApplication,
        containing expectedSubstring: String,
        timeout: TimeInterval = 8
    ) -> Bool {
        let state = app.staticTexts["quietterm.session.state"].firstMatch
        guard state.waitForExistence(timeout: timeout) else {
            return false
        }

        let predicate = NSPredicate(format: "label CONTAINS %@", expectedSubstring)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: state)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForElementCount(
        _ query: XCUIElementQuery,
        expectedCount: Int,
        timeout: TimeInterval = 8
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if query.count == expectedCount {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return query.count == expectedCount
    }
}
