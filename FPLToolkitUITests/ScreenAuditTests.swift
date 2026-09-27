import XCTest

/// Opens each main screen against the live API, attaches a screenshot, and runs Apple's
/// accessibility audit (VoiceOver labels, contrast, hit areas, Dynamic Type, clipped text).
/// Run with the FPLToolkitUITests scheme; see README "UI tests and screenshots".
///
/// `auditTeam` picks the team (default 71191) and `auditAttentionTeam` the team whose Today has
/// something to review (default 3612045). scripts/app-store-screenshots.sh passes the owner's team.
@MainActor
final class ScreenAuditTests: XCTestCase {
    // From `TEST_RUNNER_auditTeam=…` (xcodebuild passes TEST_RUNNER_* through) or `-auditTeam …`.
    private func setting(_ key: String, default value: String) -> String {
        ProcessInfo.processInfo.environment[key] ?? UserDefaults.standard.string(forKey: key) ?? value
    }
    private var team: String { setting("auditTeam", default: "71191") }
    private var attentionTeam: String { setting("auditAttentionTeam", default: "3612045") }

    override func setUp() {
        continueAfterFailure = true
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Screenshot, then audit. Any issue not listed below as a known false alarm fails the test.
    ///
    /// Known false alarms (each checked by hand, 27 Sep 2026):
    /// - Contrast on content scrolled under (or into the fade above) the translucent tab bar, behind the
    ///   pinned button bar, or under the on-screen keyboard: legible once scrolled into view.
    /// - Apple's own search field and navigation-bar buttons ("Done"): system components with system sizing.
    /// - `sizesAndLists: false` screens (sheets and List screens): the audit can't change the text size
    ///   inside them and reports every row as fixed-size or clipped, although they do resize (checked at
    ///   accessibility sizes). Contrast, labels, hit areas and traits are still audited there.
    private func check(_ app: XCUIApplication, _ name: String, sizesAndLists: Bool = true) {
        screenshot(app, name)
        let tabBar = app.tabBars.firstMatch
        // iOS 26 fades content in a band above the floating tab bar as it scrolls under it.
        let fadedFromY = tabBar.exists ? tabBar.frame.minY - 60 : .infinity
        let keyboard = app.keyboards.firstMatch
        let keyboardFrame = keyboard.exists ? keyboard.frame : .null
        let navBarFrames = app.navigationBars.allElementsBoundByIndex.map { $0.frame }
        var types = XCUIAccessibilityAuditType.all
        if !sizesAndLists { types.subtract([.dynamicType, .textClipped]) }
        do {
            try app.performAccessibilityAudit(for: types) { issue in
                guard let element = issue.element else { return false }
                let frame = element.frame
                if issue.auditType == .contrast && frame.maxY > fadedFromY { return true }
                // Covered (e.g. scrolled behind the pinned button bar): not what the user sees.
                if issue.auditType == .contrast && !element.isHittable { return true }
                // With the keyboard up, the pinned button bar (about 120 pt) sits on top of it.
                if issue.auditType == .contrast && !keyboardFrame.isNull && frame.maxY > keyboardFrame.minY - 140 { return true }
                if [.searchField, .textField].contains(element.elementType),
                   [.contrast, .textClipped].contains(issue.auditType) { return true }
                if issue.auditType == .dynamicType && navBarFrames.contains(where: { $0.intersects(frame) }) { return true }
                return false
            }
        } catch {
            XCTFail("\(name): \(error)")
        }
    }

    private func waitFor(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 20) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(what) didn't appear")
    }

    func test01WelcomeAndConnect() {
        let app = launch(["-entryId", "0"])
        let add = app.buttons["Add my FPL team"]
        waitFor(add, "Welcome")
        check(app, "01-welcome")
        add.tap()
        waitFor(app.textFields["FPL Team ID"], "Connect")
        check(app, "02-connect")
    }

    func test02TodayWithSomethingToReview() {
        let app = launch(["-entryId", attentionTeam])
        waitFor(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'to review' OR label CONTAINS[c] 'good shape'")).firstMatch, "Today")
        check(app, "03-today")
    }

    func test03Team() {
        let app = launch(["-entryId", team])
        app.tabBars.buttons["Team"].tap()
        waitFor(app.staticTexts["Goalkeeper"], "Team")
        check(app, "04-team")
    }

    func test04PlayerSheet() {
        let app = launch(["-entryId", team])
        app.tabBars.buttons["Team"].tap()
        let firstPlayer = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'GK'")).firstMatch
        waitFor(firstPlayer, "a player row")
        firstPlayer.tap()
        waitFor(app.buttons["Done"], "Player sheet")
        waitFor(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH[c] 'Next fixtures'")).firstMatch, "Player sheet content")
        check(app, "05-player", sizesAndLists: false)
    }

    func test05Watch() {
        let app = launch(["-entryId", team])
        app.tabBars.buttons["Watch"].tap()
        let follow = app.switches.firstMatch
        waitFor(follow, "Watch")
        // The switch is inactive while a saved list refreshes; it must become active (live data).
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: follow)
        waitForExpectations(timeout: 20)
        check(app, "06-watch", sizesAndLists: false)
    }

    func test06SettingsAndNotifications() {
        let app = launch(["-entryId", team, "-forcePushFeatures", "YES"])
        app.buttons["Settings"].firstMatch.tap()
        waitFor(app.buttons["Reset app data"], "Settings")
        check(app, "07-settings", sizesAndLists: false)
        app.buttons["Notifications"].tap()
        waitFor(app.staticTexts["Quiet hours"].firstMatch, "Notification settings")
        check(app, "08-notifications", sizesAndLists: false)
    }
}
