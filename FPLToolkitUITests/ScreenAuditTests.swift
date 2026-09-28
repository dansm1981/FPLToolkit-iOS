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
    /// `combinedTiles`: screens whose items are single combined elements (the planner pitch: each
    /// player is one VoiceOver element). The audit's screen-reading checks misfire there: it reports
    /// the tiles' words as "potentially inaccessible text" and measures contrast on them unreliably
    /// (even for white-on-surface text in plain view, and under the bars with no element to place).
    /// So contrast and element detection are skipped there; labels, hit areas, text sizes,
    /// clipping and traits are still audited. The tiles use the app's standard colour pairs.
    /// The Research grids (ticker, rotation, congestion) are the same: each row is one element that
    /// reads the whole row, and the cells' colour pairs were checked by hand (all 4.5:1 or better).
    /// With the keyboard up, Apple's suggestion bar ("no description") and the search field's
    /// "Clear text" button are system components too.
    /// `clippingCheckedLarge`: long player rows that wrap (the Market lists). At the default size the
    /// audit reports one or two of them as "may be clipped" although they re-flow; the same screens run
    /// at accessibility-large report no clipping and show every row whole (checked 27 Sep 2026). Only
    /// the clipping check is skipped; Dynamic Type and everything else are still audited.
    private func check(_ app: XCUIApplication, _ name: String, sizesAndLists: Bool = true, combinedTiles: Bool = false,
                       clippingCheckedLarge: Bool = false) {
        screenshot(app, name)
        let tabBar = app.tabBars.firstMatch
        // iOS 26 fades content in a band above the floating tab bar as it scrolls under it.
        let fadedFromY = tabBar.exists ? tabBar.frame.minY - 60 : .infinity
        // …and in a band below the navigation bar as content scrolls up under it.
        let fadedToY = (app.navigationBars.allElementsBoundByIndex.map { $0.frame.maxY }.max() ?? 0) + 40
        let keyboard = app.keyboards.firstMatch
        let keyboardFrame = keyboard.exists ? keyboard.frame : .null
        let navBarFrames = app.navigationBars.allElementsBoundByIndex.map { $0.frame }
        var types = XCUIAccessibilityAuditType.all
        if !sizesAndLists { types.subtract([.dynamicType, .textClipped]) }
        if combinedTiles { types.subtract([.contrast, .elementDetection]) }
        if clippingCheckedLarge { types.subtract(.textClipped) }
        do {
            try app.performAccessibilityAudit(for: types) { issue in
                guard let element = issue.element else {
                    let note = XCTAttachment(string: "no element: \(issue.compactDescription) — \(issue.detailedDescription)")
                    note.name = "AUDIT \(name)"
                    note.lifetime = .keepAlways
                    self.add(note)
                    return false
                }
                let frame = element.frame
                if issue.auditType == .contrast && frame.maxY > fadedFromY { return true }
                if issue.auditType == .contrast && frame.minY < fadedToY { return true }
                // Covered (e.g. scrolled behind the pinned button bar): not what the user sees.
                if issue.auditType == .contrast && !element.isHittable { return true }
                // With the keyboard up, the pinned button bar (about 120 pt) sits on top of it.
                if issue.auditType == .contrast && !keyboardFrame.isNull && frame.maxY > keyboardFrame.minY - 140 { return true }
                if [.searchField, .textField].contains(element.elementType),
                   [.contrast, .textClipped].contains(issue.auditType) { return true }
                if issue.auditType == .dynamicType && navBarFrames.contains(where: { $0.intersects(frame) }) { return true }
                if !keyboardFrame.isNull && keyboardFrame.intersects(frame) { return true }
                // The keyboard's suggestion strip sits just above the frame reported for the keyboard.
                if !keyboardFrame.isNull && element.label.isEmpty
                    && frame.minY >= keyboardFrame.minY - 60 && frame.maxY <= keyboardFrame.minY + 1 { return true }
                if issue.auditType == .hitRegion && element.label == "Clear text" { return true }
                // Say which element failed: the audit's own message doesn't.
                let note = XCTAttachment(string: "\(issue.compactDescription) | type \(element.elementType.rawValue) '\(element.label)' \(frame)")
                note.name = "AUDIT \(name)"
                note.lifetime = .keepAlways
                self.add(note)
                return false
            }
        } catch {
            XCTFail("\(name): \(error)")
        }
    }

    /// Lets a push or a scroll finish: the audit reads the screen, and moving text reads as faint.
    private func settle(_ seconds: TimeInterval = 1.5) {
        Thread.sleep(forTimeInterval: seconds)
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

    /// Imports the team into a draft the first time (kept on the simulator's device for later runs).
    func test08Planner() {
        let app = launch(["-entryId", team])
        app.tabBars.buttons["Planner"].tap()
        let importButton = app.buttons["Import my FPL team"].firstMatch
        let firstDraft = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'From your FPL team'")).firstMatch
        // Either the empty state or the saved draft, whichever the network brings first.
        let either = NSPredicate { _, _ in importButton.exists || firstDraft.exists }
        expectation(for: either, evaluatedWith: nil)
        waitForExpectations(timeout: 45)
        if firstDraft.exists {
            firstDraft.tap()
        } else {
            importButton.tap()
        }
        waitFor(app.staticTexts["Starting XI"].firstMatch, "Draft pitch", timeout: 40)
        settle()
        // Text sizes and clipping are audited below, with the bench in full: here the bench is cut
        // by the screen's edge, which the audit reports as clipping it can't place (checked by eye
        // at the largest sizes: nothing is cut off).
        check(app, "11-planner-draft", sizesAndLists: false, combinedTiles: true)
        // And with the bench and chips in view: the Bench heading just under the bar, so no card is
        // cut by the screen's edge (whatever sits above the pitch).
        let benchHeading = app.staticTexts.matching(NSPredicate(format: "label ==[c] 'bench'")).firstMatch
        let dy = benchHeading.frame.minY - (app.navigationBars.firstMatch.frame.maxY + 16)
        if dy > 0 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -dy)),
                        withVelocity: .slow, thenHoldForDuration: 0.5)
        }
        settle()
        check(app, "11b-planner-draft-bench", combinedTiles: true)

        // Team news for the draft's squad (audited), then FPL's own difficulty and back.
        app.scrollViews.firstMatch.swipeDown(velocity: .fast)
        app.scrollViews.firstMatch.swipeDown(velocity: .fast)
        let news = app.buttons["Team news"].firstMatch
        waitFor(news, "Team news button")
        news.tap()
        let headline = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'GW' OR label BEGINSWITH 'No news'")).firstMatch
        waitFor(headline, "Team news loaded", timeout: 40)
        settle()
        check(app, "16-draft-news")
        app.buttons["Done"].firstMatch.tap()
        let fixtures = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Fixture difficulty'")).firstMatch
        waitFor(fixtures, "Fixture switch")
        fixtures.tap()
        app.buttons["FPL FDR"].firstMatch.tap()
        waitFor(app.buttons["Fixture difficulty: FPL FDR"].firstMatch, "FPL model chosen")
        fixtures.tap()
        app.buttons["xFDR"].firstMatch.tap()
        waitFor(app.buttons["Fixture difficulty: xFDR · By position"].firstMatch, "Back to xFDR")

        // Squad evolution and the transfer timeline (both audited).
        app.buttons["Squad evolution"].firstMatch.tap()
        waitFor(app.staticTexts["Goalkeepers"].firstMatch, "Squad evolution grid", timeout: 40)
        settle()
        check(app, "17-squad-evolution", combinedTiles: true)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Transfer timeline"].firstMatch.tap()
        let timeline = app.staticTexts.matching(NSPredicate(format: "label == 'Timeline' OR label BEGINSWITH 'No changes yet'")).firstMatch
        waitFor(timeline, "Transfer timeline", timeout: 40)
        settle()
        check(app, "18-transfer-timeline")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()
        waitFor(firstDraft, "Drafts list")
        // Audit only once the draft has finished sliding away.
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["Starting XI"].firstMatch)
        waitForExpectations(timeout: 10)
        check(app, "12-planner-list", sizesAndLists: false)
    }

    /// Builds from a blank draft: "+" opens the picker, a pick lands on the pitch, the player menu
    /// removes him. Blank drafts are deleted afterwards (the imported one is kept for test08).
    func test09PlannerEditing() {
        let app = launch(["-entryId", team])
        app.tabBars.buttons["Planner"].tap()
        let newDraft = app.buttons["New draft"].firstMatch
        waitFor(newDraft, "New draft button", timeout: 30)
        newDraft.tap()
        // The sheet opens on import, with the connected Team ID filled in.
        let teamField = app.textFields["FPL Team ID"].firstMatch
        waitFor(teamField, "New draft sheet")
        XCTAssertEqual(teamField.value as? String, team)
        settle()
        check(app, "14-new-draft-sheet")
        app.buttons["Start from scratch"].firstMatch.tap()
        app.buttons["Create"].firstMatch.tap()

        let addKeeper = app.buttons["Add a goalkeeper"].firstMatch
        waitFor(addKeeper, "Blank draft", timeout: 40)
        addKeeper.tap()
        let firstKeeper = app.buttons.matching(NSPredicate(format: "label CONTAINS ' · GK · '")).firstMatch
        waitFor(firstKeeper, "Picker", timeout: 40)
        settle()
        check(app, "13-planner-picker", sizesAndLists: false)
        let name = firstKeeper.label.components(separatedBy: ",").first ?? ""
        firstKeeper.tap()

        let squadOfOne = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '1 of 15 players'")).firstMatch
        waitFor(squadOfOne, "The pick on the draft", timeout: 40)
        let empty = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '0 of 15 players'")).firstMatch

        // Undo takes the pick back off; redo puts it back.
        app.buttons["Undo"].firstMatch.tap()
        waitFor(empty, "Undo", timeout: 40)
        app.buttons["Redo"].firstMatch.tap()
        waitFor(squadOfOne, "Redo", timeout: 40)

        let tile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        waitFor(tile, "\(name) on the pitch")

        // Explore (replacing him): star another keeper for the shortlist.
        tile.tap()
        app.buttons["Replace…"].firstMatch.tap()
        let exploreTab = app.buttons["Explore"].firstMatch
        waitFor(exploreTab, "Explore tab")
        exploreTab.tap()
        waitFor(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Your shortlist'")).firstMatch, "Explore", timeout: 40)
        settle()
        check(app, "19-picker-explore", sizesAndLists: false)
        let star = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add ' AND label ENDSWITH ' to the shortlist'")).firstMatch
        waitFor(star, "A star")
        let starred = star.label.replacingOccurrences(of: "Add ", with: "").replacingOccurrences(of: " to the shortlist", with: "")
        star.tap()
        waitFor(app.buttons["Remove \(starred) from the shortlist"].firstMatch, "Starred", timeout: 20)
        app.buttons["Close"].firstMatch.tap()

        tile.tap()
        app.buttons["Remove from squad"].firstMatch.tap()
        waitFor(empty, "Squad empty again", timeout: 40)

        // The shortlist has him (audited); swipe him off again.
        app.buttons["Shortlist"].firstMatch.tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", starred)).firstMatch
        waitFor(row, "\(starred) on the shortlist", timeout: 40)
        settle()
        // A List screen: like the other lists, text sizes are checked by eye (the audit's list false alarms).
        check(app, "20-shortlist", sizesAndLists: false)
        row.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: row)
        waitForExpectations(timeout: 20)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // A chip plays, then cancels.
        let wildcard = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Wildcard 1'")).firstMatch
        for _ in 0..<4 where !(wildcard.exists && wildcard.isHittable) { app.swipeUp() }
        wildcard.tap()
        let playing = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Wildcard 1' AND label CONTAINS 'Playing in GW'")).firstMatch
        waitFor(playing, "Wildcard played", timeout: 40)
        playing.tap()
        let available = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Wildcard 1' AND label CONTAINS 'Available'")).firstMatch
        waitFor(available, "Wildcard cancelled", timeout: 40)

        // The draft menu: budget and free transfers (audited), rename, then delete.
        app.buttons["Draft options"].firstMatch.tap()
        app.buttons["Budget and free transfers…"].firstMatch.tap()
        waitFor(app.navigationBars["Budget"].firstMatch, "Budget sheet")
        settle()
        check(app, "15-draft-money")
        app.buttons["Cancel"].firstMatch.tap()

        app.buttons["Draft options"].firstMatch.tap()
        app.buttons["Rename…"].firstMatch.tap()
        let nameField = app.alerts.textFields.firstMatch
        waitFor(nameField, "Rename box")
        nameField.tap()
        nameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30) + "UI test draft")
        app.alerts.buttons["Save"].tap()
        waitFor(app.navigationBars["UI test draft"].firstMatch, "Renamed", timeout: 40)

        app.buttons["Draft options"].firstMatch.tap()
        app.buttons["Delete draft…"].firstMatch.tap()
        app.buttons["Delete draft"].firstMatch.tap()
        waitFor(app.navigationBars["Planner"].firstMatch, "Back on the drafts list", timeout: 40)
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["UI test draft"].firstMatch)
        waitForExpectations(timeout: 20)

        // Tidy up: delete any other blank draft (e.g. from an earlier failed run).
        let blanks = app.buttons.matching(NSPredicate(format: "label CONTAINS 'of 15 players'"))
        _ = blanks.firstMatch.waitForExistence(timeout: 5)
        var guardCount = 0
        while blanks.count > 0 && guardCount < 5 {
            guardCount += 1
            let before = blanks.count
            blanks.firstMatch.swipeLeft()
            app.buttons["Delete"].firstMatch.tap()
            app.buttons["Delete draft"].firstMatch.tap()
            expectation(for: NSPredicate { _, _ in blanks.count < before }, evaluatedWith: nil)
            waitForExpectations(timeout: 20)
        }
        XCTAssertEqual(blanks.count, 0, "blank drafts left behind")
    }

    /// Leagues on the Team tab: add Dan's league by ID, its Overview, Standings and "vs me"
    /// (each audited), then remove it again. The Elite 100 is always listed.
    func test10Leagues() {
        let app = launch(["-entryId", team])
        app.tabBars.buttons["Team"].tap()
        let addLeague = app.buttons["Add a league"].firstMatch
        for _ in 0..<8 where !(addLeague.exists && addLeague.isHittable) { app.swipeUp() }
        waitFor(addLeague, "Leagues on the Team tab", timeout: 40)
        waitFor(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Elite 100'")).firstMatch, "Elite 100", timeout: 40)

        let league = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'LEAGUE OF EXPERTS'")).firstMatch
        if !league.exists {
            addLeague.tap()
            let field = app.textFields["Mini-league ID"].firstMatch
            waitFor(field, "Add a league")
            field.tap()
            field.typeText("783382")
            app.buttons["Add"].firstMatch.tap()
        }
        waitFor(league, "League added", timeout: 120)
        settle()
        check(app, "21-team-leagues", sizesAndLists: false)

        league.tap()
        waitFor(app.staticTexts.matching(NSPredicate(format: "label ==[c] 'What matters to you'")).firstMatch, "Overview", timeout: 60)
        settle()
        check(app, "22-league-overview")

        app.buttons["Standings"].firstMatch.tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS ' · bench '")).firstMatch
        waitFor(row, "Standings", timeout: 60)
        settle()
        check(app, "23-league-standings")

        row.tap()
        waitFor(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] 'Squad · '")).firstMatch, "vs me", timeout: 60)
        settle()
        check(app, "24-league-vs")
        app.buttons["Done"].firstMatch.tap()

        // The remaining tabs, each audited.
        let tabs: [(String, NSPredicate, String)] = [
            ("Rivals", NSPredicate(format: "label ==[c] 'Your current rivals'"), "25-league-rivals"),
            ("Players", NSPredicate(format: "label ==[c] 'Your biggest threats'"), "26-league-players"),
            ("Captains", NSPredicate(format: "label ==[c] 'League captaincy trend'"), "27-league-captains"),
            ("Chips", NSPredicate(format: "label ==[c] 'League chip usage'"), "28-league-chips"),
            ("Transfers", NSPredicate(format: "label ==[c] 'Most bought'"), "29-league-transfers"),
            ("History", NSPredicate(format: "label ==[c] 'Season performance'"), "30-league-history"),
            ("Report", NSPredicate(format: "label ==[c] 'Share report'"), "31-league-report"),
        ]
        for (name, marker, shot) in tabs {
            app.buttons[name].firstMatch.tap()
            waitFor(app.descendants(matching: .any).matching(marker).firstMatch, "\(name) tab", timeout: 60)
            settle()
            check(app, shot)
        }

        // Back on the Team tab: touch and hold to remove the league again.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        waitFor(league, "Back on Leagues")
        league.press(forDuration: 1.2)
        app.buttons["Remove league"].firstMatch.tap()
        app.buttons["Remove league"].firstMatch.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: league)
        waitForExpectations(timeout: 30)
    }

    /// The Research tab. `auditApiBaseURL` points it at another server (a branch running locally
    /// before its endpoints are deployed).
    func test11Research() {
        var arguments = ["-entryId", team]
        let base = setting("auditApiBaseURL", default: "")
        if !base.isEmpty { arguments += ["-apiBaseURL", base] }
        let app = launch(arguments)
        app.tabBars.buttons["Research"].tap()
        let ticker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Fixture ticker'")).firstMatch
        waitFor(ticker, "Research hub")
        settle()
        check(app, "32-research-hub", sizesAndLists: false)

        ticker.tap()
        let clubRow = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS ', run total '")).firstMatch
        waitFor(clubRow, "Fixture ticker", timeout: 60)
        settle()
        check(app, "33-research-ticker", combinedTiles: true)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Rotation planner'")).firstMatch.tap()
        let add = app.buttons["Add player"].firstMatch
        waitFor(add, "Rotation planner")
        // Start from no players, so the run is the same each time.
        while let remove = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Remove '")).allElementsBoundByIndex.first {
            remove.tap()
        }
        for name in ["Cherki", "Schade"] {
            add.tap()
            let field = app.searchFields.firstMatch
            waitFor(field, "Add player")
            field.tap()
            field.typeText(name)
            let result = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
            waitFor(result, "\(name) in search", timeout: 30)
            if name == "Schade" {
                settle()
                check(app, "34-research-add-player", sizesAndLists: false)
            }
            result.tap()
        }
        let figure = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH[c] 'Rotation FDR'")).firstMatch
        waitFor(figure, "Rotation", timeout: 60)
        settle()
        check(app, "35-research-rotation", combinedTiles: true)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Congestion'")).firstMatch.tap()
        let club = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS ' in the window'")).firstMatch
        waitFor(club, "Congestion", timeout: 60)
        settle()
        check(app, "36-research-congestion", combinedTiles: true)
    }

    /// The Research tab's Market group. `auditApiBaseURL` as for test11.
    func test12Market() {
        var arguments = ["-entryId", team]
        let base = setting("auditApiBaseURL", default: "")
        if !base.isEmpty { arguments += ["-apiBaseURL", base] }
        let app = launch(arguments)
        app.tabBars.buttons["Research"].tap()
        let screens: [(String, NSPredicate, String)] = [
            ("Price changes", NSPredicate(format: "label BEGINSWITH[c] 'Price rises'"), "37-market-changes"),
            ("Predictions", NSPredicate(format: "label ==[c] 'Closest to a rise'"), "38-market-predictions"),
            ("Price and transfer trends", NSPredicate(format: "label ==[c] 'Strongest upward flow'"), "39-market-trends"),
            ("Transfers and ownership", NSPredicate(format: "label BEGINSWITH[c] 'Most bought'"), "40-market-transfers"),
        ]
        for (title, marker, shot) in screens {
            let link = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
            for _ in 0..<6 where !(link.exists && link.isHittable) { app.swipeUp() }
            waitFor(link, "\(title) on the hub")
            link.tap()
            waitFor(app.descendants(matching: .any).matching(marker).firstMatch, title, timeout: 60)
            settle()
            check(app, shot, clippingCheckedLarge: true)
            if title == "Transfers and ownership" {
                app.buttons["Ownership"].firstMatch.tap()
                waitFor(app.descendants(matching: .any).matching(NSPredicate(format: "label ==[c] 'Most owned'")).firstMatch, "Ownership")
                settle()
                check(app, "41-market-ownership", clippingCheckedLarge: true)
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    /// The Research tab's Players group. `auditApiBaseURL` as for test11.
    func test13Players() {
        var arguments = ["-entryId", team]
        let base = setting("auditApiBaseURL", default: "")
        if !base.isEmpty { arguments += ["-apiBaseURL", base] }
        let app = launch(arguments)
        app.tabBars.buttons["Research"].tap()
        let screens: [(String, NSPredicate, String)] = [
            ("Player insights", NSPredicate(format: "label BEGINSWITH[c] 'Top 12 by'"), "42-players-insights"),
            ("Template team", NSPredicate(format: "label ==[c] 'The template XI'"), "43-players-template"),
            ("Injuries", NSPredicate(format: "label BEGINSWITH[c] 'Injured ('"), "44-players-injuries"),
        ]
        for (title, marker, shot) in screens {
            let link = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
            for _ in 0..<6 where !(link.exists && link.isHittable) { app.swipeUp() }
            waitFor(link, "\(title) on the hub")
            link.tap()
            waitFor(app.descendants(matching: .any).matching(marker).firstMatch, title, timeout: 60)
            settle()
            check(app, shot, clippingCheckedLarge: true)
            if title == "Player insights" {
                // The list below the map.
                let list = app.descendants(matching: .any).matching(NSPredicate(format: "label ENDSWITH[c] ' players'")).firstMatch
                for _ in 0..<4 where !(list.exists && list.isHittable) { app.swipeUp() }
                settle()
                check(app, "45-players-insights-list", clippingCheckedLarge: true)
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
            settle(1)
        }
    }

    /// The player sheet's "More" sections, one per website player tab. `auditApiBaseURL` as for test11.
    func test14PlayerMore() {
        var arguments = ["-entryId", team]
        let base = setting("auditApiBaseURL", default: "")
        if !base.isEmpty { arguments += ["-apiBaseURL", base] }
        let app = launch(arguments)
        app.tabBars.buttons["Team"].tap()
        let player = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'DEF'")).firstMatch
        waitFor(player, "a defender")
        player.tap()
        waitFor(app.buttons["Done"], "Player sheet")
        let sections: [(String, NSPredicate, String)] = [
            ("Gameweek history", NSPredicate(format: "label ==[c] 'Every gameweek'"), "46-player-history"),
            ("Form trends", NSPredicate(format: "label ==[c] 'Rolling windows'"), "47-player-form"),
            ("Underlying stats", NSPredicate(format: "label ==[c] 'Season totals and per 90'"), "48-player-underlying"),
            ("Fixtures", NSPredicate(format: "label ==[c] 'Returns by fixture difficulty'"), "49-player-fixtures"),
            ("Price and ownership", NSPredicate(format: "label ==[c] 'Recent daily snapshots'"), "50-player-price"),
            ("DEFCON", NSPredicate(format: "label BEGINSWITH[c] 'Match by match'"), "51-player-defensive"),
            ("Vs similar players", NSPredicate(format: "label ==[c] 'Percentile ranks'"), "52-player-compare"),
        ]
        for (title, marker, shot) in sections {
            let link = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
            for _ in 0..<10 where !(link.exists && link.isHittable) { app.swipeUp() }
            waitFor(link, "\(title) on the sheet")
            link.tap()
            waitFor(app.descendants(matching: .any).matching(marker).firstMatch, title, timeout: 60)
            settle()
            check(app, shot, clippingCheckedLarge: true)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            settle(1)
        }
    }

    /// The Research tab's Elite group. `auditApiBaseURL` as for test11.
    func test15Elite() {
        var arguments = ["-entryId", team]
        let base = setting("auditApiBaseURL", default: "")
        if !base.isEmpty { arguments += ["-apiBaseURL", base] }
        let app = launch(arguments)
        app.tabBars.buttons["Research"].tap()
        let screens: [(String, NSPredicate, String)] = [
            ("Elite overview", NSPredicate(format: "label BEGINSWITH[c] 'Elite snapshot'"), "53-elite-overview"),
            ("Elite ownership", NSPredicate(format: "label ENDSWITH[c] ' players'"), "55-elite-ownership"),
            ("Elite transfers", NSPredicate(format: "label BEGINSWITH[c] 'Transfer activity'"), "57-elite-transfers"),
            ("Elite captaincy", NSPredicate(format: "label BEGINSWITH[c] 'Captaincy consensus'"), "58-elite-captaincy"),
            ("Elite template", NSPredicate(format: "label BEGINSWITH[c] 'Template squad'"), "59-elite-template"),
        ]
        for (title, marker, shot) in screens {
            let link = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
            for _ in 0..<8 where !(link.exists && link.isHittable) { app.swipeUp() }
            waitFor(link, "\(title) on the hub")
            link.tap()
            waitFor(app.descendants(matching: .any).matching(marker).firstMatch, title, timeout: 60)
            settle()
            check(app, shot, clippingCheckedLarge: true)
            if title == "Elite overview" || title == "Elite ownership" {
                // The lists further down.
                app.swipeUp()
                app.swipeUp()
                settle()
                check(app, title == "Elite overview" ? "54-elite-overview-lists" : "56-elite-ownership-list",
                      clippingCheckedLarge: true)
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
            settle(1)
        }
    }

    func test07ExploreWithoutATeam() {
        let app = launch(["-entryId", "0", "-exploring", "YES"])
        waitFor(app.buttons["Add my FPL team"].firstMatch, "Explore Today")
        check(app, "09-explore-today")
        app.tabBars.buttons["Team"].tap()
        waitFor(app.staticTexts["Add your FPL team"].firstMatch, "Explore Team")
        check(app, "10-explore-team")
    }
}
