import UIKit
import XCTest

/// Not an audit: every main screen from top to bottom, a screenshot per screenful, for a design
/// review. Skipped unless `TEST_RUNNER_reviewCapture=1`; scripts/review-screens.sh runs it with the
/// audit and exports the screenshots. Attachments are named `rNN-slug~PP` (screen, then page).
///
/// Works against the live API with `reviewTeam` (default: the audit's team). The helpers
/// mirror ScreenAuditTests' (slow drags down the left margin, so nothing is tapped by accident).
@MainActor
final class ReviewCaptureTests: XCTestCase {
    private nonisolated func setting(_ key: String, default value: String) -> String {
        ProcessInfo.processInfo.environment[key] ?? UserDefaults.standard.string(forKey: key) ?? value
    }
    private var team: String { setting("reviewTeam", default: setting("auditTeam", default: "71191")) }
    private var attentionTeam: String { setting("auditAttentionTeam", default: "3612045") }

    override func setUpWithError() throws {
        let requested = setting("reviewCapture", default: "0") == "1"
        try XCTSkipUnless(requested, "Review capture runs only on request")
        continueAfterFailure = true
    }

    // MARK: - Screens

    func testR01FirstRun() {
        var app = launch(["-entryId", "0"])
        let add = app.buttons["Add my FPL team"]
        waitFor(add, "Welcome")
        capture(app, "r01-welcome")
        add.tap()
        waitFor(app.textFields["FPL Team ID"], "Connect")
        settle()
        capture(app, "r02-connect", pages: 1)

        app = launch(["-entryId", "0", "-exploring", "YES"])
        waitFor(app.buttons["Add my FPL team"].firstMatch, "Explore Today")
        capture(app, "r03-explore-today")
        app.tabBars.buttons["Team"].tap()
        waitFor(app.staticTexts["Add your FPL team"].firstMatch, "Explore Team")
        capture(app, "r04-explore-team")
    }

    func testR02Today() {
        var app = launch(["-entryId", team])
        waitFor(app.buttons.matching(NSPredicate(format: "label == 'View gameweek' OR label == 'Open Matchday'")).firstMatch, "Today", timeout: 60)
        settle(3)
        capture(app, "r10-today")

        // Season history, from the gameweek card's score (batch 2).
        let history = app.buttons["season-history"].firstMatch
        if history.waitForExistence(timeout: 10) {
            history.tap()
            waitFor(app.navigationBars["Season history"].firstMatch, "Season history", timeout: 40)
            settle(3)
            capture(app, "r12-season-history")
        }

        app = launch(["-entryId", attentionTeam])
        waitFor(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'No new squad alerts' OR label CONTAINS 'In your GW'")).firstMatch, "Today")
        settle(3)
        capture(app, "r11-today-other-team")
    }

    func testR03TeamAndPlayer() {
        func openTeam(_ layout: String = "Pitch") -> XCUIApplication {
            let app = launch(["-entryId", team])
            app.tabBars.buttons["Team"].tap()
            waitFor(app.buttons[layout].firstMatch, "Team")
            app.buttons[layout].firstMatch.tap()
            settle(2)
            return app
        }
        func setMetric(_ app: XCUIApplication, _ metric: String) {
            let menu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Show on tiles'")).firstMatch
            waitFor(menu, "Show on tiles", timeout: 30)
            menu.tap()
            let option = app.buttons[metric].firstMatch
            waitFor(option, metric)
            option.tap()
            settle()
        }
        var app = openTeam()
        setMetric(app, "Fixtures")
        capture(app, "r20-team")
        app = openTeam()
        setMetric(app, "Odds")
        capture(app, "r21-team-odds")
        app = openTeam()
        setMetric(app, "Price")
        capture(app, "r21b-team-price")
        app = openTeam("List")
        capture(app, "r21c-team-list")
        app = openTeam("Fixtures")
        settle(3)
        capture(app, "r21d-team-fixtures")

        app = openTeam()
        setMetric(app, "Odds")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Show on tiles'")).firstMatch.tap()
        let oddsCheck = app.buttons["Odds check"].firstMatch
        waitFor(oddsCheck, "Odds check in the menu")
        oddsCheck.tap()
        waitFor(app.staticTexts.matching(NSPredicate(format: "label ==[c] 'Captain options'")).firstMatch, "Odds check", timeout: 30)
        settle()
        capture(app, "r22-odds-check")

        for (position, name) in [("Defender", "r23-player-defender"), ("Forward", "r24-player-forward")] {
            app = openTeam()
            setMetric(app, "Fixtures")
            let tile = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", ", \(position)")).firstMatch
            reveal(tile, in: app)
            tile.tap()
            waitFor(app.buttons["Overview"].firstMatch, "Player page")
            settle(3)
            capture(app, name)
            for tab in ["Stats", "Fixtures"] {
                app.buttons[tab].firstMatch.tap()
                settle(2)
                capture(app, name + "-" + tab.lowercased())
            }
        }
    }

    /// The player sheet's "More" pages, for a defender (DEFCON applies).
    func testR04PlayerMore() {
        let app = launch(["-entryId", team])
        app.tabBars.buttons["Team"].tap()
        let player = app.buttons.matching(NSPredicate(format: "label CONTAINS ', Defender'")).firstMatch
        waitFor(player, "a defender", timeout: 30)
        player.tap()
        waitFor(app.buttons["Stats"].firstMatch, "Player page")
        app.buttons["Stats"].firstMatch.tap()
        let pages: [(String, NSPredicate, String)] = [
            ("Gameweek history", NSPredicate(format: "label ==[c] 'Every gameweek'"), "r25-player-history"),
            ("Form trends", NSPredicate(format: "label ==[c] 'Rolling windows'"), "r26-player-form"),
            ("Underlying stats", NSPredicate(format: "label ==[c] 'Season totals and per 90'"), "r27-player-underlying"),
            ("Fixtures", NSPredicate(format: "label ==[c] 'Returns by fixture difficulty'"), "r28-player-fixtures"),
            ("Price and ownership", NSPredicate(format: "label ==[c] 'Recent daily snapshots'"), "r29-player-price"),
            ("DEFCON", NSPredicate(format: "label BEGINSWITH[c] 'Match by match'"), "r30-player-defcon"),
            ("Vs similar players", NSPredicate(format: "label ==[c] 'Percentile ranks'"), "r31-player-compare"),
        ]
        for (title, marker, name) in pages {
            let link = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
            reveal(link, in: app)
            link.tap()
            let screen = app.descendants(matching: .any).matching(marker).firstMatch
            waitFor(screen, title, timeout: 60)
            settle()
            capture(app, name)
            back(app, leaving: screen)
        }
    }

    func testR05Leagues() {
        let app = launch(["-entryId", team])
        app.tabBars.buttons["Team"].tap()
        let leaguesButton = app.buttons["Your leagues"].firstMatch
        waitFor(leaguesButton, "Your leagues button", timeout: 40)
        leaguesButton.tap()
        let addLeague = app.buttons["Add a league"].firstMatch
        waitFor(addLeague, "Your leagues", timeout: 40)
        settle()
        capture(app, "r39-your-leagues", pages: 2)
        let league = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'LEAGUE OF EXPERTS'")).firstMatch
        let added = !league.exists
        if added {
            addLeague.tap()
            let field = app.textFields["Mini-league ID"].firstMatch
            waitFor(field, "Add a league")
            field.tap()
            field.typeText("783382")
            app.buttons["Add"].firstMatch.tap()
        }
        waitFor(league, "League added", timeout: 120)
        reveal(league, in: app)
        league.tap()
        waitFor(app.staticTexts.matching(NSPredicate(format: "label ==[c] 'What matters to you'")).firstMatch, "Overview", timeout: 60)
        settle()
        capture(app, "r40-league-overview")

        let tabs: [(String, NSPredicate, String)] = [
            ("Standings", NSPredicate(format: "label CONTAINS ' · bench '"), "r41-league-standings"),
            ("Rivals", NSPredicate(format: "label ==[c] 'Your current rivals'"), "r43-league-rivals"),
            ("Players", NSPredicate(format: "label ==[c] 'Your biggest threats'"), "r44-league-players"),
            ("Captains", NSPredicate(format: "label ==[c] 'League captaincy trend'"), "r45-league-captains"),
            ("Chips", NSPredicate(format: "label ==[c] 'League chip usage'"), "r46-league-chips"),
            ("Transfers", NSPredicate(format: "label ==[c] 'Most bought'"), "r47-league-transfers"),
            ("History", NSPredicate(format: "label ==[c] 'Season performance'"), "r48-league-history"),
            ("Report", NSPredicate(format: "label ==[c] 'Share report'"), "r49-league-report"),
        ]
        for (tab, marker, name) in tabs {
            let tabButton = app.buttons[tab].firstMatch
            reveal(tabButton, in: app)
            tabButton.tap()
            let screen = app.descendants(matching: .any).matching(marker).firstMatch
            waitFor(screen, "\(tab) tab", timeout: 60)
            settle()
            capture(app, name)
            if tab == "Standings" {
                let row = app.buttons.matching(NSPredicate(format: "label CONTAINS ' · bench '")).firstMatch
                reveal(row, in: app)
                row.tap()
                waitFor(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] 'Squad · '")).firstMatch, "vs me", timeout: 60)
                settle()
                capture(app, "r42-league-vs")
                app.buttons["Done"].firstMatch.tap()
            }
        }

        if added {
            app.navigationBars.buttons.element(boundBy: 0).tap()
            waitFor(league, "Back on Leagues")
            reveal(league, in: app)
            league.press(forDuration: 1.2)
            app.buttons["Remove league"].firstMatch.tap()
            app.buttons["Remove league"].firstMatch.tap()
        }
    }

    func testR06Matchday() {
        let app = launch(["-entryId", team])
        let card = app.buttons.matching(NSPredicate(format: "label == 'View gameweek' OR label == 'Open Matchday'")).firstMatch
        waitFor(card, "Gameweek on Today", timeout: 60)
        card.tap()
        waitFor(app.buttons["Your team"].firstMatch, "Matchday", timeout: 60)
        settle()
        capture(app, "r50-matchday")
        for mode in ["Live feed", "Matches"] {
            app.buttons[mode].firstMatch.tap()
            settle()
            capture(app, "r50-matchday-" + mode.lowercased().replacingOccurrences(of: " ", with: "-"))
        }
        app.buttons["Your team"].firstMatch.tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS ' point'")).firstMatch
        reveal(row, in: app)
        row.tap()
        waitFor(app.staticTexts["FPL-recorded"].firstMatch, "Points breakdown")
        settle()
        capture(app, "r51-matchday-breakdown")
    }

    func testR07Planner() {
        let app = launch(["-entryId", team])
        app.tabBars.buttons["Planner"].tap()
        let firstDraft = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'From your FPL team'")).firstMatch
        waitFor(firstDraft, "Planner drafts", timeout: 45)
        settle()
        capture(app, "r60-planner-drafts")
        firstDraft.tap()
        waitFor(app.staticTexts["Starting XI"].firstMatch, "Draft pitch", timeout: 40)
        settle(3)
        capture(app, "r61-planner-draft")
    }

    /// Every row of the Research hub, in the hub's order.
    func testR08Research() {
        let app = launch(["-entryId", team])
        app.tabBars.buttons["Research"].tap()
        waitFor(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Fixture ticker'")).firstMatch, "Research hub")
        settle()
        capture(app, "r70-research-hub")
        let rows: [(String, NSPredicate?)] = [
            ("Fixture ticker", NSPredicate(format: "label CONTAINS ', run total '")),
            ("Rotation planner", NSPredicate(format: "label ==[c] 'Add player'")),
            ("Congestion", NSPredicate(format: "label CONTAINS ' in the window'")),
            ("Player insights", NSPredicate(format: "label CONTAINS ', Pts '")),
            ("Template team", NSPredicate(format: "label ==[c] 'The template XI'")),
            ("Injuries", NSPredicate(format: "label BEGINSWITH[c] 'Injured ('")),
            ("Price changes", NSPredicate(format: "label BEGINSWITH[c] 'Price rises'")),
            ("Predictions", NSPredicate(format: "label ==[c] 'Closest to a rise'")),
            ("Price and transfer trends", NSPredicate(format: "label ==[c] 'Strongest upward flow'")),
            ("Transfers and ownership", NSPredicate(format: "label BEGINSWITH[c] 'Most bought'")),
            // One Elite home since batch 3; its pages open from there.
            ("Elite 100", NSPredicate(format: "label BEGINSWITH 'Elite overview,'")),
            ("DEFCON", NSPredicate(format: "label ==[c] 'DEFCON leaderboard'")),
            ("Hauls", NSPredicate(format: "label ==[c] 'Most 10+ point gameweeks'")),
            ("Consistency", NSPredicate(format: "label ==[c] 'Most consistent returners'")),
            ("Home and away", NSPredicate(format: "label ==[c] 'Home specialists'")),
            ("Records", NSPredicate(format: "label ==[c] 'Biggest single gameweek scores'")),
        ]
        for (index, (title, marker)) in rows.enumerated() {
            let link = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(title),")).firstMatch
            reveal(link, in: app)
            guard link.exists else { XCTFail("\(title) not on the hub"); continue }
            link.tap()
            let screen = marker.map { app.descendants(matching: .any).matching($0).firstMatch }
            if let screen { waitFor(screen, title, timeout: 60) }
            settle(screen == nil ? 5 : 2)
            capture(app, "r\(71 + index)-" + title.lowercased().replacingOccurrences(of: " ", with: "-"), pages: 8)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            waitFor(app.navigationBars["Research"].firstMatch, "Back on the hub")
            settle(1)
        }
    }

    func testR09WatchAndSettings() {
        var app = launch(["-entryId", team])
        app.tabBars.buttons["Watch"].tap()
        waitFor(app.switches.firstMatch, "Watch")
        settle(3)
        capture(app, "r97-watch")
        let alerts = app.buttons["See all alerts"].firstMatch
        reveal(alerts, in: app)
        if alerts.exists {
            alerts.tap()
            settle(3)
            capture(app, "r98-alerts")
        }

        app = launch(["-entryId", team, "-forcePushFeatures", "YES"])
        app.buttons["Settings"].firstMatch.tap()
        waitFor(app.buttons["Reset app data"], "Settings")
        settle()
        capture(app, "r99-settings")
        // Back up by revealing the row, not by dragging to the top: Settings may be a sheet.
        let notifications = app.buttons["Notifications"]
        reveal(notifications, in: app)
        notifications.tap()
        waitFor(app.staticTexts["Quiet hours"].firstMatch, "Notification settings")
        settle()
        capture(app, "r99b-notifications")
    }

    // MARK: - Capture

    /// A screenshot per screenful, from where the screen is now to its end: drags of about half a
    /// screen (so pages overlap) until a drag moves nothing, or `pages` screenshots.
    private func capture(_ app: XCUIApplication, _ name: String, pages: Int = 10) {
        var previous: Data?
        for page in 1...pages {
            let shot = app.screenshot()
            let body = content(of: shot)
            if body != nil && body == previous { return }
            previous = body
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = String(format: "%@~%02d", name, page)
            attachment.lifetime = .keepAlways
            add(attachment)
            guard page < pages else { return }
            let height = app.frame.height
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 8, dy: height * 0.72))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -height * 0.45)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
            settle(1.2)
        }
    }

    /// The screenshot without the status bar, to tell whether a drag moved anything.
    private func content(of shot: XCUIScreenshot) -> Data? {
        let image = shot.image
        guard let cg = image.cgImage else { return nil }
        let top = Int(70 * image.scale)
        guard let cropped = cg.cropping(to: CGRect(x: 0, y: top, width: cg.width, height: cg.height - top)) else { return nil }
        return UIImage(cgImage: cropped).pngData()
    }

    // MARK: - Helpers (as in ScreenAuditTests)

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func settle(_ seconds: TimeInterval = 1.5) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func waitFor(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 20) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(what) didn't appear")
    }

    private func back(_ app: XCUIApplication, leaving screen: XCUIElement) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: screen)
        waitForExpectations(timeout: 15)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for attempt in 0..<30 {
            let tabBar = app.tabBars.firstMatch
            let tabBarShows = tabBar.exists && tabBar.isHittable
            let top = (app.navigationBars.allElementsBoundByIndex.map { $0.frame.maxY }.max() ?? 0) + 8
            let bottom = (tabBarShows ? tabBar.frame.minY : app.frame.maxY) - 8
            let middle = (top + bottom) / 2
            let page = (bottom - top) * 0.6
            let step: CGFloat
            if element.exists {
                let frame = element.frame
                if frame.minY >= top && frame.maxY <= bottom && element.isHittable { return }
                if abs(frame.midY - middle) < 40 {
                    settle(0.5)
                    continue
                }
                step = max(-page, min(page, frame.midY - middle))
            } else {
                step = attempt < 12 ? page : -page
            }
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: 8, dy: middle + step / 2))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -step)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
        }
    }
}
