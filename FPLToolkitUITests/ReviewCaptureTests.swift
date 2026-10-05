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
    /// A folder name: each screenshot is also written to the test runner's own temporary folder
    /// under review/<name>/, to copy out with `simctl get_app_container … data`, for when the
    /// result bundle can't be read (it stalled finalising on 4 Oct). The runner can't write to the
    /// Mac's folders directly.
    private var reviewOut: URL? {
        let name = setting("reviewOut", default: "")
        guard !name.isEmpty else { return nil }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("review").appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

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
        openMyTeam(app)
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
            openMyTeam(app)
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
        openMyTeam(app)
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
        openMyTeam(app)
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

    /// The Planner workspace (Dan's concept, 5 Oct): the plan top to bottom, its views, and the
    /// plan switcher.
    func testR07Planner() {
        var app = launch(["-entryId", team])
        openPlanner(app)
        let plan = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Plan: '")).firstMatch
        waitFor(plan, "A plan", timeout: 45)
        app.buttons["Pitch"].firstMatch.tap()
        settle(3)
        capture(app, "r60-planner-plan", pages: 8)
        for layout in ["List", "Fixtures"] {
            app = launch(["-entryId", team])
            openPlanner(app)
            app.buttons[layout].firstMatch.tap()
            settle(3)
            capture(app, "r61-planner-" + layout.lowercased(), pages: 4)
        }
        app = launch(["-entryId", team])
        openPlanner(app)
        app.buttons["Pitch"].firstMatch.tap()
        plan.tap()
        waitFor(app.navigationBars["Switch plan"].firstMatch, "Switch plan")
        settle()
        capture(app, "r64-planner-switch", pages: 2)
    }

    /// Projections ("results first, depth on demand", 5 Oct): the list, its menus, the run's
    /// details and filters, then a forecast with playing time adjusted and every section open, and
    /// the player page's way in.
    func testR10Projections() {
        func open() -> (XCUIApplication, XCUIElement) {
            let app = launch(["-entryId", team])
            app.tabBars.buttons["Projections"].tap()
            let row = app.buttons.matching(NSPredicate(format: "label CONTAINS '80% range'")).firstMatch
            waitFor(row, "Projections list", timeout: 60)
            settle(2)
            return (app, row)
        }
        var (app, row) = open()
        capture(app, "r80-projections", pages: 4)

        // The run's details (ⓘ) and the filters.
        (app, row) = open()
        app.buttons.matching(NSPredicate(format: "label CONTAINS ' · updated '")).firstMatch.tap()
        waitFor(app.navigationBars["About these projections"].firstMatch, "Run details")
        settle()
        capture(app, "r81-projections-about", pages: 6)
        app.buttons["Done"].firstMatch.tap()
        settle(2)
        app.buttons["Filters"].firstMatch.tap()
        waitFor(app.navigationBars["Filters"].firstMatch, "Filters")
        settle()
        capture(app, "r82-projections-filters", pages: 2)
        app.buttons["Done"].firstMatch.tap()
        settle(2)

        // The gameweeks and players menus, open.
        for (prefix, name) in [("Gameweeks", "r83-projections-gameweeks-menu"), ("Players", "r84-projections-players-menu")] {
            let chip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
            chip.tap()
            settle()
            capture(app, name, pages: 1)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
            settle(1)
        }
        // Next 3 gameweeks, defenders.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Gameweeks'")).firstMatch.tap()
        let next3 = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Next 3'")).firstMatch
        waitFor(next3, "Next 3 in the menu")
        next3.tap()
        settle(1)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Players'")).firstMatch.tap()
        let defenders = app.buttons["Defenders"].firstMatch
        waitFor(defenders, "Defenders in the menu")
        defenders.tap()
        waitFor(app.buttons.matching(NSPredicate(format: "label CONTAINS 'at least one 10 point'")).firstMatch, "Next 3 rows", timeout: 60)
        settle(2)
        capture(app, "r85-projections-next3-def", pages: 2)

        // A forecast: adjust playing time, then every section open.
        (app, row) = open()
        reveal(row, in: app)
        row.tap()
        let outcomes = app.buttons["Possible outcomes"].firstMatch
        waitFor(outcomes, "Player forecast", timeout: 60)
        settle(2)
        capture(app, "r86-projection-forecast", pages: 3)
        let adjust = app.buttons["Adjust playing time"].firstMatch
        reveal(adjust, in: app)
        adjust.tap()
        let setFull = app.buttons["Set 100%"].firstMatch
        waitFor(setFull, "Minutes sheet")
        settle()
        capture(app, "r87-projections-minutes", pages: 1)
        setFull.tap()
        app.buttons["Done"].firstMatch.tap()
        settle(2)
        for title in ["Points by source", "Playing-time assumptions", "Match context and rates", "More figures", "Over the horizon"] {
            let section = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
            reveal(section, in: app)
            section.tap()
            settle(1)
        }
        // From the top, with your forecast and every section open.
        for _ in 0..<6 { app.swipeDown() }
        settle(1)
        capture(app, "r89-projection-forecast-open", pages: 12)

        // Back on the list, the row says it's yours.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        waitFor(app.buttons.matching(NSPredicate(format: "label CONTAINS 'your forecast'")).firstMatch, "A row with your forecast", timeout: 60)
        settle(2)
        capture(app, "r88-projections-tweaked", pages: 1)

        // The player page's way in.
        (app, row) = open()
        reveal(row, in: app)
        row.tap()
        waitFor(app.buttons["Possible outcomes"].firstMatch, "Player forecast", timeout: 60)
        let playerPage = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Open ' AND label CONTAINS 'player page'")).firstMatch
        reveal(playerPage, in: app)
        playerPage.tap()
        waitFor(app.buttons["Overview"].firstMatch, "Player page", timeout: 40)
        settle(3)
        capture(app, "r90-player-projected-points", pages: 2)
    }

    /// Your FPL team, read-only (from the switcher): top to bottom, then Team news and Squad rotation.
    func testR07bPlannerLanding() {
        var app = launch(["-entryId", team])
        openMyTeam(app)
        settle(3)
        capture(app, "r59-fpl-team", pages: 8)
        for (button, marker, name) in [("Team news", "Team news", "r62-team-news"), ("Squad rotation", "Squad rotation", "r63-squad-rotation")] {
            app = launch(["-entryId", team])
            openMyTeam(app)
            let b = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", button)).firstMatch
            reveal(b, in: app)
            b.tap()
            waitFor(app.navigationBars[marker].firstMatch, marker, timeout: 40)
            settle(3)
            capture(app, name, pages: 3)
        }
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
            if let reviewOut {
                try? shot.pngRepresentation.write(to: reviewOut.appendingPathComponent(attachment.name! + ".png"))
            }
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

    /// Your FPL team: read-only, from the plan switcher on the Planner tab (Dan's concept, 5 Oct).
    private func openMyTeam(_ app: XCUIApplication) {
        app.tabBars.buttons["Planner"].tap()
        let plan = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Plan: '")).firstMatch
        let teamRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'FPL team'")).firstMatch
        let addTeam = app.staticTexts["Add your FPL team"].firstMatch
        let either = NSPredicate { _, _ in plan.exists || teamRow.exists || addTeam.exists }
        expectation(for: either, evaluatedWith: nil)
        waitForExpectations(timeout: 45)
        if addTeam.exists && !plan.exists { return }
        if !teamRow.exists {
            plan.tap()
            waitFor(app.navigationBars["Switch plan"].firstMatch, "Switch plan")
            // Exploring without a team: the switcher offers to add one instead.
            if addTeam.waitForExistence(timeout: 3) && !teamRow.exists { return }
        }
        teamRow.tap()
        waitFor(app.navigationBars["FPL team"].firstMatch, "FPL team")
        settle(1)
    }

    /// The Planner tab: your plan, or the start card when there's none.
    private func openPlanner(_ app: XCUIApplication) {
        app.tabBars.buttons["Planner"].tap()
        let plan = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Plan: '")).firstMatch
        let importButton = app.buttons["Import my FPL team"].firstMatch
        let either = NSPredicate { _, _ in plan.exists || importButton.exists }
        expectation(for: either, evaluatedWith: nil)
        waitForExpectations(timeout: 45)
        settle(1)
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
