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
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        // With TEST_RUNNER_auditOut=<name>, also saved in the runner's temporary folder under
        // audit/<name>/, to copy out with `simctl get_app_container … data` (the result bundle
        // stalled finalising on 4 Oct).
        let out = setting("auditOut", default: "")
        if !out.isEmpty {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("audit").appendingPathComponent(out)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: dir.appendingPathComponent(name + ".png"))
        }
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
                    // Text found in the screenshot with no element to match: the design's gradients
                    // (screen glow, card lift) set this off on screens whose accessibility tree is
                    // unchanged (they pass with flat backgrounds), and it names no place to check.
                    // Recorded above; not a failure.
                    // Contrast with no element is the same: nothing to place it (the checks below skip
                    // text faded under the tab bar only when they can see where it is), and on Today it
                    // came and went between runs of the same build. Recorded above; not a failure.
                    return issue.compactDescription == "Potentially inaccessible text"
                        || issue.auditType == .contrast
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
                // A manager's own team name (e.g. "Mohame4d.sayed") is shown as they wrote it.
                if issue.compactDescription == "Label not human-readable" && element.elementType == .staticText { return true }
                // Over the screen glow and the cards' lift the audit takes two gradient shades for
                // text and background, so text that spans both "fails" at about 1:1. Measure the
                // element's own pixels instead; below 4.5:1 it still fails.
                if issue.auditType == .contrast, let ratio = self.measuredContrast(of: element, in: app), ratio >= 4.5 {
                    let note = XCTAttachment(string: "Contrast measured \(String(format: "%.1f", ratio)):1 | '\(element.label)' \(frame)")
                    note.name = "CONTRAST \(name)"
                    note.lifetime = .keepAlways
                    self.add(note)
                    return true
                }
                // Say which element failed: the audit's own message doesn't. Printed too, so the log
                // has it when the result bundle can't be read (it stalled finalising on 4 Oct).
                let text = "\(issue.compactDescription) | type \(element.elementType.rawValue) '\(element.label)' \(frame)"
                print("AUDIT \(name): \(text)")
                let note = XCTAttachment(string: text)
                note.name = "AUDIT \(name)"
                note.lifetime = .keepAlways
                self.add(note)
                return false
            }
        } catch {
            XCTFail("\(name): \(error)")
        }
    }

    /// WCAG contrast from an element's pixels: the background is the median luminance, the text
    /// the far tail on either side (the 0.5% most extreme, so a stray pixel doesn't count).
    private func measuredContrast(of element: XCUIElement, in app: XCUIApplication) -> Double? {
        // Only an element wholly on screen: a screenshot of one partly off it can stop the test runner.
        let frame = element.frame
        guard !frame.isEmpty, frame.width >= 2, frame.height >= 2, app.frame.contains(frame) else { return nil }
        guard let image = element.screenshot().image.cgImage, image.width > 0, image.height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        func linear(_ value: UInt8) -> Double {
            let c = Double(value) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        var luminance: [Double] = []
        luminance.reserveCapacity(width * height)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            luminance.append(0.2126 * linear(pixels[i]) + 0.7152 * linear(pixels[i + 1]) + 0.0722 * linear(pixels[i + 2]))
        }
        luminance.sort()
        let background = luminance[luminance.count / 2]
        let tail = Int(Double(luminance.count - 1) * 0.005)
        func ratio(_ a: Double, _ b: Double) -> Double { (max(a, b) + 0.05) / (min(a, b) + 0.05) }
        return max(ratio(luminance[luminance.count - 1 - tail], background), ratio(luminance[tail], background))
    }

    /// Lets a push or a scroll finish: the audit reads the screen, and moving text reads as faint.
    private func settle(_ seconds: TimeInterval = 1.5) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// The Team tab remembers its view; the pitch tests start from Pitch.
    private func showPitch(_ app: XCUIApplication) {
        let pitch = app.buttons["Pitch"].firstMatch
        waitFor(pitch, "Team views", timeout: 40)
        pitch.tap()
    }

    private func waitFor(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 20) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(what) didn't appear")
    }

    /// Brings an element of a long list into plain view, clear of the navigation bar and the tab bar,
    /// with slow drags by the distance still to go. A flick (`swipeUp`) can carry a row past the
    /// screen or leave it under the floating tab bar, and a List drops rows scrolled far away, so an
    /// element that isn't there is looked for down the list first, then back up.
    ///
    /// The drags run down the left margin, clear of the rows: in a ScrollView a slow drag that starts
    /// on a link ends on it too (the row moves with the finger) and opens it.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for attempt in 0..<24 {
            // A sheet covers the tab bar; the sheet's content then runs to the bottom of the screen.
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
                    // Where it should be, but not hittable yet (still moving).
                    settle(0.5)
                    continue
                }
                step = max(-page, min(page, frame.midY - middle))
            } else {
                step = attempt < 8 ? page : -page
            }
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: 8, dy: middle + step / 2))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -step)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
        }
    }

    /// Goes back from a pushed screen, and waits until it's gone: a list searched while it's still
    /// sliding back in reports rows at the wrong places.
    private func back(_ app: XCUIApplication, leaving screen: XCUIElement) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: screen)
        waitForExpectations(timeout: 15)
    }

    /// The Research tab's hub.
    /// Your FPL team: read-only, from the plan switcher on the Planner tab since 5 Oct (Dan's
    /// concept), or straight from the start card when there's no plan yet.
    private func openMyTeam(_ app: XCUIApplication) {
        app.tabBars.buttons["Planner"].tap()
        let plan = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Plan: '")).firstMatch
        let teamRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'FPL team'")).firstMatch
        let addTeam = app.staticTexts["Add your FPL team"].firstMatch
        let either = NSPredicate { _, _ in plan.exists || teamRow.exists || addTeam.exists }
        expectation(for: either, evaluatedWith: nil)
        waitForExpectations(timeout: 45)
        // Exploring without a team: the Planner says so, with the add-team card.
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

    /// Opens the plan's ⋯ menu and taps an item in it.
    private func planMenu(_ app: XCUIApplication, _ item: String) {
        app.buttons["Plan options"].firstMatch.tap()
        let button = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", item)).firstMatch
        waitFor(button, "\(item) in the plan menu")
        button.tap()
    }

    private func openResearch(_ app: XCUIApplication) {
        app.tabBars.buttons["Research"].tap()
        waitFor(app.navigationBars["Research"].firstMatch, "Research hub")
    }

    /// Opens a row of the Research hub. Its label is the title, a comma, then the detail; matching
    /// the comma keeps "Elite template" from finding "Elite template race".
    private func openHubRow(_ app: XCUIApplication, _ title: String) {
        let link = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(title),")).firstMatch
        reveal(link, in: app)
        waitFor(link, "\(title) on the hub")
        link.tap()
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
        waitFor(app.staticTexts["Your next move"].firstMatch, "Today", timeout: 40)
        settle()
        check(app, "03-today")
        // "Your rival": the starred rival, or the pick-a-rival suggestion when there isn't one.
        let rival = app.staticTexts["Your rival"].firstMatch
        if rival.waitForExistence(timeout: 15) {
            reveal(rival, in: app)
            settle()
            check(app, "03b-today-rival")
        }
    }

    /// My Team, its sheets and the pitch. `auditApiBaseURL` as for test11 (e.g. a branch's Team
    /// news sparklines before they're live).
    func test03Team() {
        var arguments = ["-entryId", team]
        let base = setting("auditApiBaseURL", default: "")
        if !base.isEmpty { arguments += ["-apiBaseURL", base] }
        let app = launch(arguments)
        openMyTeam(app)
        showPitch(app)
        waitFor(app.buttons.matching(NSPredicate(format: "label CONTAINS ', Goalkeeper'")).firstMatch, "Squad", timeout: 30)
        settle()
        // Tiles cut by the floating tab bar read as clipping the audit can't place; checked by eye at
        // the largest standard size (names and chips wrap inside the tiles; 29 Sep 2026).
        check(app, "04-team", combinedTiles: true, clippingCheckedLarge: true)

        // ◀ ▶ (batch 3): the tiles move on a gameweek and back. The arrows are for fixtures, and
        // earlier tests may leave the tiles on Odds or Price (the choice is kept).
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Show on tiles:'")).firstMatch.tap()
        let auto = app.buttons["xFDR · Auto"].firstMatch
        waitFor(auto, "Fixture difficulty choices")
        auto.tap()
        let shown = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Tiles show gameweek'")).firstMatch
        waitFor(shown, "Gameweek arrows")
        let before = shown.label
        app.buttons["Next gameweek"].firstMatch.tap()
        XCTAssertNotEqual(shown.label, before, "The arrows move the tiles to the next gameweek")
        app.buttons["Previous gameweek"].firstMatch.tap()
        XCTAssertEqual(shown.label, before)

        // Team news and Squad rotation (batch 3), one tap from the squad.
        app.buttons["Team news"].firstMatch.tap()
        waitFor(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'squad' AND label CONTAINS 'attention'")).firstMatch,
                "Team news", timeout: 30)
        settle()
        check(app, "04d-team-news", sizesAndLists: false)
        app.buttons["Done"].firstMatch.tap()

        app.buttons["Squad rotation"].firstMatch.tap()
        waitFor(app.staticTexts["Goalkeepers"].firstMatch, "Squad rotation grid", timeout: 40)
        settle()
        check(app, "04e-team-rotation", combinedTiles: true)
        app.buttons["Done"].firstMatch.tap()

        // List (Dan, 29 Sep): every figure for each player, no menu of layers.
        app.buttons["List"].firstMatch.tap()
        waitFor(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Odds are betting-market'")).firstMatch,
                "Team list", timeout: 30)
        settle()
        check(app, "04b-team-list", clippingCheckedLarge: true)

        // Fixtures: the compact grid, with the difficulty choices in plain view.
        app.buttons["Fixtures"].firstMatch.tap()
        waitFor(app.buttons["Official FDR"].firstMatch, "Fixture choices", timeout: 30)
        waitFor(app.staticTexts["Player"].firstMatch, "Fixture grid", timeout: 40)
        settle()
        // A table of cells sized with the text (@ScaledMetric), one line each: like the lists, its
        // text sizes are checked by eye at the largest standard size, not by the audit.
        check(app, "04c-team-fixtures", sizesAndLists: false)
    }

    func test04PlayerSheet() {
        let app = launch(["-entryId", team])
        openMyTeam(app)
        showPitch(app)
        let firstPlayer = app.buttons.matching(NSPredicate(format: "label CONTAINS ', Goalkeeper'")).firstMatch
        waitFor(firstPlayer, "a goalkeeper on the pitch", timeout: 30)
        firstPlayer.tap()
        waitFor(app.buttons["Overview"].firstMatch, "Player page")
        waitFor(app.staticTexts["Next fixtures"].firstMatch, "Player page content")
        settle()
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

        // In your squad (batch 3): news as the team news cards.
        let squad = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] 'In your squad'")).firstMatch
        for _ in 0..<3 where !(squad.exists && squad.isHittable) { app.swipeUp() }
        settle()
        check(app, "06c-watch-squad", sizesAndLists: false)
        for _ in 0..<3 { app.swipeDown() }
        // (Watch → "Manage alerts" was removed 7 Oct: alerts live in Settings → Notifications, test06.)
    }

    func test06SettingsAndNotifications() {
        let app = launch(["-entryId", team, "-forcePushFeatures", "YES"])
        app.buttons["Settings"].firstMatch.tap()
        waitFor(app.buttons["Reset app data"], "Settings")
        check(app, "07-settings", sizesAndLists: false)
        app.buttons["Notifications"].tap()
        // The first alert switch: with the Matchday section, quiet hours start below the fold.
        waitFor(app.switches.matching(NSPredicate(format: "label BEGINSWITH 'Price projections'")).firstMatch,
                "Notification settings")
        check(app, "08-notifications", sizesAndLists: false)

        // Matchday alerts (tasks/push.md stage 2): the master switch shows one switch per kind.
        // Turned back off afterwards, so the simulator's device keeps its settings.
        let matchday = app.switches.matching(NSPredicate(format: "label BEGINSWITH 'Matchday alerts'")).firstMatch
        reveal(matchday, in: app)
        // A SwiftUI switch toggles from its control, not its label.
        if (matchday.value as? String) != "1" { matchday.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap() }
        // Presets, then every switch under "Choose each alert" (possibly below the fold).
        let normal = app.buttons["Normal"].firstMatch
        reveal(normal, in: app)
        waitFor(normal, "Matchday presets")
        normal.tap()
        settle()
        XCTAssertTrue(normal.isSelected, "Normal applies")
        let choose = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Choose each alert'")).firstMatch
        reveal(choose, in: app)
        choose.tap()
        let goals = app.switches.matching(NSPredicate(format: "label BEGINSWITH 'Goals'")).firstMatch
        reveal(goals, in: app)
        waitFor(goals, "Matchday alert kinds")
        settle()
        check(app, "08b-notifications-matchday", sizesAndLists: false)
        reveal(matchday, in: app)
        matchday.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: goals)
        waitForExpectations(timeout: 15)

        // Live matchday (Dan, 2 Oct): who Matchday watches; rivals are the saved ones (Stage B).
        reveal(app.buttons["Live matchday"].firstMatch, in: app)
        app.buttons["Live matchday"].firstMatch.tap()
        let owned = app.switches.matching(NSPredicate(format: "label BEGINSWITH 'Highly owned'")).firstMatch
        waitFor(owned, "Live matchday")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Your rivals'")).firstMatch.exists)
        settle()
        check(app, "08c-live-matchday", sizesAndLists: false)
    }

    /// Imports the team into a draft the first time (kept on the simulator's device for later runs).
    func test08Planner() {
        let app = launch(["-entryId", team])
        openPlanner(app)
        let plan = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Plan: '")).firstMatch
        if !plan.exists {
            app.buttons["Import my FPL team"].firstMatch.tap()
            waitFor(plan, "The imported plan", timeout: 40)
        }
        // The plan switcher (audited); the imported plan on screen.
        plan.tap()
        waitFor(app.navigationBars["Switch plan"].firstMatch, "Switch plan")
        settle()
        check(app, "12-planner-switch", sizesAndLists: false)
        let imported = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'From your FPL team'")).firstMatch
        if imported.exists { imported.tap() } else { app.buttons["Done"].firstMatch.tap() }
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.navigationBars["Switch plan"].firstMatch)
        waitForExpectations(timeout: 10)

        app.buttons["Pitch"].firstMatch.tap()
        waitFor(app.staticTexts["This week's fixtures · xFDR"].firstMatch, "Plan pitch", timeout: 40)
        settle()
        // Text sizes and clipping are audited below, with the bench in full: here the bench is cut
        // by the screen's edge, which the audit reports as clipping it can't place (checked by eye
        // at the largest sizes: nothing is cut off).
        check(app, "11-planner-draft", sizesAndLists: false, combinedTiles: true)
        // And with the bench, chip and transfers in view: the Bench heading just under the bar.
        let benchHeading = app.staticTexts.matching(NSPredicate(format: "label ==[c] 'bench'")).firstMatch
        let dy = benchHeading.frame.minY - (app.navigationBars.firstMatch.frame.maxY + 16)
        if dy > 0 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -dy)),
                        withVelocity: .slow, thenHoldForDuration: 0.5)
        }
        settle()
        check(app, "11b-planner-draft-bench", combinedTiles: true, clippingCheckedLarge: true)

        // List and Fixtures views of the plan.
        app.scrollViews.firstMatch.swipeDown(velocity: .fast)
        app.scrollViews.firstMatch.swipeDown(velocity: .fast)
        app.buttons["List"].firstMatch.tap()
        settle()
        check(app, "11c-planner-list", clippingCheckedLarge: true)
        app.buttons["Fixtures"].firstMatch.tap()
        waitFor(app.staticTexts["Player"].firstMatch, "Plan fixture grid", timeout: 40)
        settle()
        // A table of cells sized with the text, one line each: text sizes checked by eye (as Team's).
        check(app, "11d-planner-fixtures", sizesAndLists: false)
        app.buttons["Pitch"].firstMatch.tap()

        // Team news for the plan's squad (audited), from the plan's menu.
        planMenu(app, "Team news")
        let headline = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'GW' OR label BEGINSWITH 'No news'")).firstMatch
        waitFor(headline, "Team news loaded", timeout: 40)
        settle()
        // A sheet: the audit can't resize text inside it (see check()); checked by eye at xxxLarge bold.
        check(app, "16-draft-news", sizesAndLists: false)
        app.buttons["Done"].firstMatch.tap()
        settle()

        // FPL's own difficulty and back, from the menu.
        planMenu(app, "Fixture difficulty")
        app.buttons["Official FDR"].firstMatch.tap()
        settle()
        app.buttons["Plan options"].firstMatch.tap()
        waitFor(app.buttons["Fixture difficulty: Official FDR"].firstMatch, "Official FDR chosen")
        app.buttons["Fixture difficulty: Official FDR"].firstMatch.tap()
        app.buttons["xFDR"].firstMatch.tap()
        settle()
        app.buttons["Plan options"].firstMatch.tap()
        waitFor(app.buttons["Fixture difficulty: xFDR · Auto"].firstMatch, "Back to xFDR")
        // Close the menu.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
        settle()

        // Squad rotation (menu) and the transfer timeline (the transfers row), both audited.
        planMenu(app, "Squad rotation")
        waitFor(app.staticTexts["Goalkeepers"].firstMatch, "Squad rotation grid", timeout: 40)
        settle()
        // Screenshot only: the same grid is audited from the team in test03, and its audit can stall
        // for many minutes under load (5 Oct), which held this whole test up.
        screenshot(app, "17-squad-rotation")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        settle()
        let transfers = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Transfer timeline' OR label CONTAINS ' transfer'")).firstMatch
        reveal(transfers, in: app)
        transfers.tap()
        let timeline = app.staticTexts.matching(NSPredicate(format: "label == 'Timeline' OR label BEGINSWITH 'No changes yet'")).firstMatch
        waitFor(timeline, "Transfer timeline", timeout: 40)
        settle()
        check(app, "18-transfer-timeline")
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    /// Builds from a blank plan: "+" opens the picker, a pick lands on the pitch, the player menu
    /// removes him. Blank plans are deleted afterwards (the imported one is kept for test08).
    func test09PlannerEditing() {
        let app = launch(["-entryId", team])
        openPlanner(app)
        let plan = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Plan: '")).firstMatch
        // A new plan from the switcher (with plans) or the start card's "another Team ID" (without).
        if plan.exists {
            plan.tap()
            waitFor(app.navigationBars["Switch plan"].firstMatch, "Switch plan")
            app.buttons["New plan"].firstMatch.tap()
        } else {
            app.buttons["Import another team’s ID…"].firstMatch.tap()
        }
        // The sheet opens on import, with the connected Team ID filled in.
        let teamField = app.textFields["FPL Team ID"].firstMatch
        waitFor(teamField, "New draft sheet")
        XCTAssertEqual(teamField.value as? String, team)
        settle()
        check(app, "14-new-draft-sheet")
        app.buttons["Start from scratch"].firstMatch.tap()
        app.buttons["Create"].firstMatch.tap()

        let addKeeper = app.buttons["Add a goalkeeper"].firstMatch
        waitFor(addKeeper, "Blank plan", timeout: 40)
        addKeeper.tap()
        // A picker row reads "Name, Club, £4.5m, 34 points, …".
        let firstKeeper = app.buttons.matching(NSPredicate(format: "label MATCHES '.*, £[0-9.]+m, [0-9]+ points.*'")).firstMatch
        waitFor(firstKeeper, "Picker", timeout: 40)
        settle()
        check(app, "13-planner-picker", sizesAndLists: false)
        let name = firstKeeper.label.components(separatedBy: ",").first ?? ""
        firstKeeper.tap()

        let squadOfOne = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '1 of 15 players'")).firstMatch
        waitFor(squadOfOne, "The pick on the plan", timeout: 40)
        let empty = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '0 of 15 players'")).firstMatch

        // Undo takes the pick back off; redo (in the plan's menu) puts it back.
        app.buttons["Undo"].firstMatch.tap()
        waitFor(empty, "Undo", timeout: 40)
        planMenu(app, "Redo")
        waitFor(squadOfOne, "Redo", timeout: 40)

        let tile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        waitFor(tile, "\(name) on the pitch")

        // Explore (replacing him): star another keeper for the shortlist.
        tile.tap()
        app.buttons["Replace…"].firstMatch.tap()
        // The picker's own control: a bare "Explore" can match a button behind the sheet.
        let exploreTab = app.segmentedControls.buttons["Explore"].firstMatch
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

        // The shortlist (plan menu) has him (audited); swipe him off again.
        planMenu(app, "Shortlist")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", starred)).firstMatch
        waitFor(row, "\(starred) on the shortlist", timeout: 40)
        settle()
        // A List screen: like the other lists, text sizes are checked by eye (the audit's list false alarms).
        check(app, "20-shortlist", sizesAndLists: false)
        row.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: row)
        waitForExpectations(timeout: 20)

        // All players (batch 3): the shared finder, with a star on every player.
        app.segmentedControls.buttons["All players"].firstMatch.tap()
        waitFor(app.buttons.matching(NSPredicate(format: "label CONTAINS ', Pts '")).firstMatch,
                "All players", timeout: 40)
        settle()
        check(app, "20b-shortlist-all", clippingCheckedLarge: true)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // A chip plays, then cancels, from "Chip: None ▾".
        let chip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Chip: '")).firstMatch
        reveal(chip, in: app)
        chip.tap()
        app.buttons["Play Wildcard 1"].firstMatch.tap()
        let playing = app.buttons["Chip: Wildcard 1"].firstMatch
        waitFor(playing, "Wildcard played", timeout: 40)
        playing.tap()
        app.buttons["Cancel Wildcard 1"].firstMatch.tap()
        waitFor(app.buttons["Chip: none"].firstMatch, "Wildcard cancelled", timeout: 40)

        // The plan menu: budget and free transfers (audited), rename, then delete.
        app.scrollViews.firstMatch.swipeDown(velocity: .fast)
        app.scrollViews.firstMatch.swipeDown(velocity: .fast)
        planMenu(app, "Bank and free transfers…")
        waitFor(app.navigationBars["Bank"].firstMatch, "Bank sheet")
        settle()
        check(app, "15-draft-money")
        app.buttons["Cancel"].firstMatch.tap()
        settle()

        planMenu(app, "Rename…")
        let nameField = app.alerts.textFields.firstMatch
        waitFor(nameField, "Rename box")
        nameField.tap()
        nameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30) + "UI test draft")
        app.alerts.buttons["Save"].tap()
        waitFor(app.buttons["Plan: UI test draft"].firstMatch, "Renamed", timeout: 40)

        planMenu(app, "Delete plan…")
        app.buttons["Delete plan"].firstMatch.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["Plan: UI test draft"].firstMatch)
        waitForExpectations(timeout: 40)

        // Tidy up: delete any other blank plan (e.g. from an earlier failed run), from the switcher.
        openPlanner(app)
        let current = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Plan: '")).firstMatch
        guard current.exists else { return }
        current.tap()
        waitFor(app.navigationBars["Switch plan"].firstMatch, "Switch plan")
        let blanks = app.buttons.matching(NSPredicate(format: "label CONTAINS 'of 15 players' AND NOT (label BEGINSWITH 'Options for')"))
        _ = blanks.firstMatch.waitForExistence(timeout: 5)
        var guardCount = 0
        while blanks.count > 0 && guardCount < 5 {
            guardCount += 1
            let before = blanks.count
            let blankName = blanks.firstMatch.label.components(separatedBy: ",").first ?? ""
            app.buttons["Options for \(blankName)"].firstMatch.tap()
            app.buttons["Delete…"].firstMatch.tap()
            app.buttons["Delete plan"].firstMatch.tap()
            expectation(for: NSPredicate { _, _ in blanks.count < before }, evaluatedWith: nil)
            waitForExpectations(timeout: 20)
        }
        XCTAssertEqual(blanks.count, 0, "blank plans left behind")
        app.buttons["Done"].firstMatch.tap()
    }

    /// Leagues on the Team tab: add Dan's league by ID, its Overview, Standings and "vs me"
    /// (each audited), then remove it again. The Elite 100 is always listed.
    func test10Leagues() {
        let app = launch(["-entryId", team])
        openMyTeam(app)
        let leaguesButton = app.buttons["Your leagues"].firstMatch
        waitFor(leaguesButton, "Your leagues button", timeout: 40)
        leaguesButton.tap()
        let addLeague = app.buttons["Add a league"].firstMatch
        waitFor(addLeague, "Your leagues", timeout: 40)
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
            ("Around you", NSPredicate(format: "label ==[c] 'Closest to you'"), "25-league-around-you"),
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

        // Back on Your leagues: touch and hold to remove the league again.
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
        openResearch(app)
        let ticker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Fixture ticker'")).firstMatch
        waitFor(ticker, "Research hub")
        settle()
        check(app, "32-research-hub", sizesAndLists: false)

        openHubRow(app, "Fixture ticker")
        let clubRow = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS ', run total '")).firstMatch
        waitFor(clubRow, "Fixture ticker", timeout: 60)
        settle()
        check(app, "33-research-ticker", combinedTiles: true)
        back(app, leaving: clubRow)

        openHubRow(app, "Rotation planner")
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
        back(app, leaving: figure)

        openHubRow(app, "Congestion")
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
        openResearch(app)
        let screens: [(String, NSPredicate, String)] = [
            ("Price changes", NSPredicate(format: "label BEGINSWITH[c] 'Price rises'"), "37-market-changes"),
            ("Predictions", NSPredicate(format: "label ==[c] 'Closest to a rise'"), "38-market-predictions"),
            ("Price and transfer trends", NSPredicate(format: "label ==[c] 'Strongest upward flow'"), "39-market-trends"),
            ("Transfers and ownership", NSPredicate(format: "label BEGINSWITH[c] 'Most bought'"), "40-market-transfers"),
        ]
        for (title, marker, shot) in screens {
            openHubRow(app, title)
            var screen = app.descendants(matching: .any).matching(marker).firstMatch
            waitFor(screen, title, timeout: 60)
            settle()
            check(app, shot, clippingCheckedLarge: true)
            if title == "Transfers and ownership" {
                app.buttons["Ownership"].firstMatch.tap()
                screen = app.descendants(matching: .any).matching(NSPredicate(format: "label ==[c] 'Most owned'")).firstMatch
                waitFor(screen, "Ownership")
                settle()
                check(app, "41-market-ownership", clippingCheckedLarge: true)
            }
            back(app, leaving: screen)
        }
    }

    /// The Research tab's Players group. `auditApiBaseURL` as for test11.
    /// Expected stats (happy-backend-pal#73): the xG table, then players by xG. `auditApiBaseURL`
    /// as for test11.
    func test23ExpectedStats() {
        var arguments = ["-entryId", team]
        let base = setting("auditApiBaseURL", default: "")
        if !base.isEmpty { arguments += ["-apiBaseURL", base] }
        let app = launch(arguments)
        openResearch(app)
        openHubRow(app, "Expected stats")
        // A team row reads "1, Man City, 15 points from 5 matches, …".
        let teamRow = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS ' points from '")).firstMatch
        waitFor(teamRow, "Expected stats teams", timeout: 60)
        settle()
        check(app, "90-expected-teams")
        app.buttons["Players"].firstMatch.tap()
        let playerRow = app.buttons.matching(NSPredicate(format: "label CONTAINS ' xG, '")).firstMatch
        waitFor(playerRow, "Expected stats players", timeout: 60)
        settle()
        check(app, "91-expected-players", clippingCheckedLarge: true)
    }

    func test24Projections() {
        var arguments = ["-entryId", team]
        let base = setting("auditApiBaseURL", default: "")
        if !base.isEmpty { arguments += ["-apiBaseURL", base] }
        let app = launch(arguments)
        // Its own tab since 4 Oct (Dan); "results first, depth on demand" since 5 Oct.
        app.tabBars.buttons["Projections"].tap()
        // A row reads "Saka. Projected 5.1 points, 80% range 2 to 10. …".
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS '80% range'")).firstMatch
        waitFor(row, "Projections list", timeout: 60)
        settle()
        check(app, "92-projections", clippingCheckedLarge: true)
        reveal(row, in: app)
        settle()
        check(app, "92b-projections-rows", clippingCheckedLarge: true)

        // The run's details behind ⓘ, and the filters: sheets (see check()).
        let info = app.buttons.matching(NSPredicate(format: "label CONTAINS ' · updated '")).firstMatch
        reveal(info, in: app)
        info.tap()
        waitFor(app.navigationBars["About these projections"].firstMatch, "Run details")
        settle()
        check(app, "92c-projections-info", sizesAndLists: false)
        app.buttons["Done"].firstMatch.tap()
        // Let the sheet go before reading the screen again (its bar vanishes mid-read otherwise).
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.navigationBars["About these projections"].firstMatch)
        waitForExpectations(timeout: 10)
        settle()
        let filters = app.buttons["Filters"].firstMatch
        reveal(filters, in: app)
        filters.tap()
        waitFor(app.navigationBars["Filters"].firstMatch, "Filters")
        settle()
        check(app, "92d-projections-filters", sizesAndLists: false)
        app.buttons["Done"].firstMatch.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.navigationBars["Filters"].firstMatch)
        waitForExpectations(timeout: 10)
        settle()

        // The forecast, and your playing time from it.
        reveal(row, in: app)
        row.tap()
        let outcomes = app.buttons["Possible outcomes"].firstMatch
        waitFor(outcomes, "Player forecast", timeout: 60)
        settle()
        check(app, "94-projection-player", clippingCheckedLarge: true)
        let adjust = app.buttons["Adjust playing time"].firstMatch
        reveal(adjust, in: app)
        adjust.tap()
        let setFull = app.buttons["Set 100%"].firstMatch
        waitFor(setFull, "Minutes forecast sheet")
        settle()
        // A sheet: the audit can't change the text size inside it (see check()); checked by eye at
        // xxxLarge bold, where it wraps and the buttons stack.
        check(app, "93-projection-minutes", sizesAndLists: false)
        setFull.tap()
        app.buttons["Done"].firstMatch.tap()
        waitFor(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Your forecast.'")).firstMatch, "Your forecast on the forecast")
        settle()

        // Depth on demand: open the sections.
        for title in ["Points by source", "Playing-time assumptions", "Over the horizon"] {
            let section = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
            reveal(section, in: app)
            section.tap()
            settle(1)
        }
        let horizon = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Over the horizon'")).firstMatch
        reveal(horizon, in: app)
        settle()
        check(app, "95-projection-player-more", clippingCheckedLarge: true)

        // Back on the list: the row and the chip say it's yours.
        back(app, leaving: outcomes)
        let tweaked = app.buttons.matching(NSPredicate(format: "label CONTAINS 'your forecast'")).firstMatch
        waitFor(tweaked, "A row with your forecast", timeout: 60)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Remove filter: Your minutes'")).firstMatch.exists)
    }

    func test13Players() {
        var arguments = ["-entryId", team]
        let base = setting("auditApiBaseURL", default: "")
        if !base.isEmpty { arguments += ["-apiBaseURL", base] }
        let app = launch(arguments)
        openResearch(app)
        let screens: [(String, NSPredicate, String)] = [
            // Opens on every player since batch 3: a row reads "Name, Pts 34, …".
            ("Player insights", NSPredicate(format: "label CONTAINS ', Pts '"), "42-players-insights"),
            ("Template team", NSPredicate(format: "label ==[c] 'The template XI'"), "43-players-template"),
            ("Injuries", NSPredicate(format: "label BEGINSWITH[c] 'Injured ('"), "44-players-injuries"),
        ]
        for (title, marker, shot) in screens {
            openHubRow(app, title)
            let screen = app.descendants(matching: .any).matching(marker).firstMatch
            waitFor(screen, title, timeout: 60)
            settle()
            check(app, shot, clippingCheckedLarge: true)
            if title == "Player insights" {
                // Further down the list.
                app.swipeUp()
                settle()
                check(app, "45-players-insights-list", clippingCheckedLarge: true)
            }
            back(app, leaving: screen)
        }
    }

    /// The player sheet's "More" sections, one per website player tab. `auditApiBaseURL` as for test11.
    func test14PlayerMore() {
        var arguments = ["-entryId", team]
        let base = setting("auditApiBaseURL", default: "")
        if !base.isEmpty { arguments += ["-apiBaseURL", base] }
        let app = launch(arguments)
        openMyTeam(app)
        // The position as a player row writes it: a looser match also finds "Odds check: captain,
        // defence, bench" while the odds overlay is on (test20 leaves it on).
        showPitch(app)
        let player = app.buttons.matching(NSPredicate(format: "label CONTAINS ', Defender'")).firstMatch
        waitFor(player, "a defender", timeout: 30)
        player.tap()
        waitFor(app.buttons["Stats"].firstMatch, "Player page")
        app.buttons["Stats"].firstMatch.tap()
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
            reveal(link, in: app)
            waitFor(link, "\(title) on the sheet")
            link.tap()
            let screen = app.descendants(matching: .any).matching(marker).firstMatch
            waitFor(screen, title, timeout: 60)
            settle()
            check(app, shot, clippingCheckedLarge: true)
            back(app, leaving: screen)
        }
    }

    /// The Research tab's Elite group. `auditApiBaseURL` as for test11.
    func test15Elite() {
        var arguments = ["-entryId", team]
        let base = setting("auditApiBaseURL", default: "")
        if !base.isEmpty { arguments += ["-apiBaseURL", base] }
        let app = launch(arguments)
        openResearch(app)
        // One Elite home since batch 3, with a card for every Elite page.
        openHubRow(app, "Elite 100")
        waitFor(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Elite overview, Median GW points'")).firstMatch,
                "Elite home", timeout: 60)
        settle()
        check(app, "52-elite-home", clippingCheckedLarge: true)
        let screens: [(String, NSPredicate, String)] = [
            ("You vs Elite", NSPredicate(format: "label BEGINSWITH[c] 'Template overlap'"), "52b-you-vs-elite"),
            ("Elite vs overall", NSPredicate(format: "label BEGINSWITH[c] 'The Elite back more'"), "52c-elite-gaps"),
            ("Elite overview", NSPredicate(format: "label BEGINSWITH[c] 'Elite snapshot'"), "53-elite-overview"),
            ("Elite ownership", NSPredicate(format: "label ENDSWITH[c] ' players'"), "55-elite-ownership"),
            ("Elite transfers", NSPredicate(format: "label BEGINSWITH[c] 'Transfer activity'"), "57-elite-transfers"),
            ("Elite captaincy", NSPredicate(format: "label BEGINSWITH[c] 'Captaincy consensus'"), "58-elite-captaincy"),
            ("Elite template", NSPredicate(format: "label BEGINSWITH[c] 'Template squad'"), "59-elite-template"),
        ]
        for (title, marker, shot) in screens {
            openHubRow(app, title)
            let screen = app.descendants(matching: .any).matching(marker).firstMatch
            waitFor(screen, title, timeout: 60)
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
            back(app, leaving: screen)
        }
    }

    /// The Elite group's season screens. `auditApiBaseURL` as for test11.
    func test16EliteSeason() {
        var arguments = ["-entryId", team]
        let base = setting("auditApiBaseURL", default: "")
        if !base.isEmpty { arguments += ["-apiBaseURL", base] }
        let app = launch(arguments)
        openResearch(app)
        openHubRow(app, "Elite 100")
        let screens: [(String, NSPredicate, String)] = [
            ("Elite template race", NSPredicate(format: "label BEGINSWITH[c] 'Elite ownership race'"), "60-elite-race"),
            ("Elite movers", NSPredicate(format: "label BEGINSWITH[c] 'Biggest 1 GW risers'"), "62-elite-movers"),
            ("Elite comparison", NSPredicate(format: "label ==[c] 'Add player'"), "63-elite-compare"),
            ("Elite chips", NSPredicate(format: "label BEGINSWITH[c] 'Chips played in GW'"), "65-elite-chips"),
            ("Elite squad structure", NSPredicate(format: "label BEGINSWITH[c] 'Value and shape'"), "66-elite-structure"),
            ("Elite trends", NSPredicate(format: "label ==[c] 'Season shape'"), "67-elite-trends"),
        ]
        for (title, marker, shot) in screens {
            openHubRow(app, title)
            let screen = app.descendants(matching: .any).matching(marker).firstMatch
            waitFor(screen, title, timeout: 60)
            settle()
            if title == "Elite comparison" {
                // Start from no players, so the run is the same each time, then chart two.
                while let remove = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Remove '")).allElementsBoundByIndex.first {
                    remove.tap()
                }
                for name in ["Haaland", "Palmer"] {
                    app.buttons["Add player"].firstMatch.tap()
                    let field = app.searchFields.firstMatch
                    waitFor(field, "Add player")
                    field.tap()
                    field.typeText(name)
                    let result = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
                    waitFor(result, "\(name) in search", timeout: 30)
                    result.tap()
                }
                waitFor(app.descendants(matching: .any).matching(NSPredicate(format: "label ==[c] 'Players'")).firstMatch,
                        "Comparison chart", timeout: 60)
                settle()
            }
            check(app, shot, clippingCheckedLarge: true)
            if title == "Elite template race" || title == "Elite comparison" {
                // The rows under the chart. A slow drag, not a flick, so the list is still when audited.
                let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
                from.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)),
                           withVelocity: .slow, thenHoldForDuration: 0.3)
                settle()
                check(app, title == "Elite template race" ? "61-elite-race-standings" : "64-elite-compare-players",
                      clippingCheckedLarge: true)
            }
            back(app, leaving: screen)
        }
    }

    /// The DEFCON screen. `auditApiBaseURL` as for test11 (the full base, ending /api/mobile/v1/).
    func test17Defcon() {
        var arguments = ["-entryId", team]
        let base = setting("auditApiBaseURL", default: "")
        if !base.isEmpty { arguments += ["-apiBaseURL", base] }
        let app = launch(arguments)
        openResearch(app)
        openHubRow(app, "DEFCON")
        waitFor(app.descendants(matching: .any).matching(NSPredicate(format: "label ==[c] 'DEFCON leaderboard'")).firstMatch,
                "DEFCON", timeout: 60)
        settle()
        check(app, "68-defcon", clippingCheckedLarge: true)
        // Further down: the leaderboard's rows, then the reliability map and its list. Slow drags, so
        // the list is still when audited.
        func drag() {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            from.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        drag()
        settle()
        check(app, "69-defcon-leaderboard", clippingCheckedLarge: true)
        // Bring the map's heading to just under the navigation bar: drag by exactly the distance, a
        // screen at a time, with no momentum.
        let map = app.descendants(matching: .any).matching(NSPredicate(format: "label ==[c] 'DEFCON reliability map'")).firstMatch
        for _ in 0..<12 {
            let delta = map.frame.minY - 140
            if abs(delta) < 30 { break }
            let step = max(-450, min(450, delta))
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: step > 0 ? 0.8 : 0.3))
            from.press(forDuration: 0.1, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -step)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        settle()
        check(app, "70-defcon-map", clippingCheckedLarge: true)
        drag()
        settle()
        check(app, "71-defcon-map-list", clippingCheckedLarge: true)
    }

    /// The deep dives. `auditApiBaseURL` as for test17.
    func test18DeepDives() {
        var arguments = ["-entryId", team]
        let base = setting("auditApiBaseURL", default: "")
        if !base.isEmpty { arguments += ["-apiBaseURL", base] }
        let app = launch(arguments)
        openResearch(app)
        let screens: [(String, NSPredicate, String)] = [
            ("Hauls", NSPredicate(format: "label ==[c] 'Most 10+ point gameweeks'"), "72-deep-hauls"),
            ("Consistency", NSPredicate(format: "label ==[c] 'Most consistent returners'"), "73-deep-consistency"),
            ("Home and away", NSPredicate(format: "label ==[c] 'Home specialists'"), "74-deep-home-away"),
            ("Records", NSPredicate(format: "label ==[c] 'Biggest single gameweek scores'"), "75-deep-records"),
        ]
        for (title, marker, shot) in screens {
            openHubRow(app, title)
            let screen = app.descendants(matching: .any).matching(marker).firstMatch
            waitFor(screen, title, timeout: 60)
            settle()
            check(app, shot, clippingCheckedLarge: true)
            back(app, leaving: screen)
        }
    }

    /// Matchday (Phase 3, P3-3): opened from the Today card; the score, moments and live squad, and
    /// one player's points breakdown. `auditApiBaseURL` as for test11.
    func test19Matchday() {
        var arguments = ["-entryId", team]
        let base = setting("auditApiBaseURL", default: "")
        if !base.isEmpty { arguments += ["-apiBaseURL", base] }
        let app = launch(arguments)
        let card = app.buttons.matching(NSPredicate(format: "label == 'View gameweek' OR label == 'Open Matchday'")).firstMatch
        waitFor(card, "Gameweek on Today", timeout: 60)
        card.tap()
        let moments = app.buttons["Your team"].firstMatch
        waitFor(moments, "Matchday", timeout: 60)
        settle()
        check(app, "76-matchday")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS ' point'")).firstMatch
        reveal(row, in: app)
        row.tap()
        waitFor(app.staticTexts["FPL-recorded"].firstMatch, "Points breakdown")
        settle()
        check(app, "77-matchday-breakdown")
        // The sheet's Done (Matchday behind it has one too).
        let done = app.buttons.matching(NSPredicate(format: "label == 'Done'"))
        done.element(boundBy: done.count - 1).tap()
    }

    /// Odds (Phase 3, P3-5): the Team tab's "Show odds" switch and the odds check sheet. Needs odds
    /// loaded for the next gameweek (48 hours before a deadline, or loaded early).
    /// A live matchday replay frozen halfway (happy-backend-pal#58): Today and Matchday in their
    /// live states, which a finished gameweek never shows. Skipped when the server has no matchday
    /// recorded in the last 30 days. `auditApiBaseURL` as for test11.
    func test21MatchdayReplay() async throws {
        let base = setting("auditApiBaseURL", default: "https://www.fpltoolkit.co.uk/api/mobile/v1/")
        let url = try XCTUnwrap(URL(string: base)?.appending(path: "live/replays"))
        let (data, _) = try await URLSession.shared.data(from: url)
        struct Item: Decodable { let id: String }
        struct Payload: Decodable { let replays: [Item] }
        struct List: Decodable { let data: Payload }
        let replays = try JSONDecoder().decode(List.self, from: data).data.replays
        // A stretch of play (not the whole gameweek), halfway through: matches in progress.
        // `auditReplay` picks one (e.g. gw5-2, Saturday's matches).
        let chosen = setting("auditReplay", default: "")
        guard let id = replays.first(where: { $0.id == chosen })?.id
                ?? replays.first(where: { !$0.id.hasSuffix("-all") })?.id ?? replays.first?.id else {
            throw XCTSkip("No matchday recorded in the last 30 days")
        }

        // Players to watch (happy-backend-pal#66), and the device's saved rivals (#68: test22
        // features Andy for team 22615).
        var arguments = ["-entryId", team, "-liveReplayId", id, "-liveReplayFreeze", "600",
                         "-matchdayWatch", "owned,elite"]
        if base != "https://www.fpltoolkit.co.uk/api/mobile/v1/" { arguments += ["-apiBaseURL", base] }
        let app = launch(arguments)
        let end = app.buttons["End replay"].firstMatch
        waitFor(end, "Replay on Today", timeout: 60)
        settle()
        check(app, "80-today-replay", sizesAndLists: false)

        let card = app.buttons.matching(NSPredicate(format: "label == 'View gameweek' OR label == 'Open Matchday'")).firstMatch
        waitFor(card, "Gameweek on Today", timeout: 30)
        card.tap()
        waitFor(app.buttons["Your team"].firstMatch, "Matchday", timeout: 60)
        waitFor(end, "Replay on Matchday", timeout: 30)
        settle()
        check(app, "81-matchday-replay")
        // Your rivals under the bench (the featured contest), then players to watch.
        let rivals = app.staticTexts["Your rivals"].firstMatch
        if rivals.waitForExistence(timeout: 10) {
            reveal(rivals, in: app)
            settle()
            check(app, "81b-matchday-rivals")
        }
        let watching = app.staticTexts["Players to watch"].firstMatch
        reveal(watching, in: app)
        settle()
        check(app, "81c-matchday-watching")
        for _ in 0..<4 { app.swipeDown() }
        settle()
        app.buttons["Matches"].firstMatch.tap()
        settle()
        check(app, "82-matchday-replay-matches")
        // The live feed (happy-backend-pal#61) ten minutes into a stretch of play.
        app.buttons["Live feed"].firstMatch.tap()
        settle()
        check(app, "83-matchday-replay-feed")
    }

    /// Rivals (happy-backend-pal#67): Watch → Rivals, adding a manager from a saved league (the
    /// simulator's device keeps League of Experts), then their page's three tabs. Pass
    /// `auditTeam=22615` (Dan's team, in that league). The rival stays saved on this device.
    /// Matchday v2's Pulse (tasks/matchday-v2.md phase 0), behind Settings → Developer: a replay
    /// frozen halfway with `-matchday.v2 YES`. What matters now, Live now, Just happened and the
    /// featured rival. `auditReplay` as for test21.
    func test25MatchdayPulse() async throws {
        let url = URL(string: "https://www.fpltoolkit.co.uk/api/mobile/v1/live/replays")!
        let (data, _) = try await URLSession.shared.data(from: url)
        struct Item: Decodable { let id: String }
        struct Payload: Decodable { let replays: [Item] }
        struct List: Decodable { let data: Payload }
        let replays = try JSONDecoder().decode(List.self, from: data).data.replays
        let chosen = setting("auditReplay", default: "gw5-2")
        guard let id = replays.first(where: { $0.id == chosen })?.id ?? replays.first?.id else {
            throw XCTSkip("No matchday the server can replay")
        }
        let app = launch(["-entryId", team, "-liveReplayId", id, "-liveReplayFreeze", "600", "-matchday.v2", "YES"])
        waitFor(app.buttons["End replay"].firstMatch, "Replay on Today", timeout: 60)
        let card = app.buttons.matching(NSPredicate(format: "label == 'View gameweek' OR label == 'Open Matchday'")).firstMatch
        waitFor(card, "Gameweek on Today", timeout: 30)
        card.tap()
        waitFor(app.buttons["Pulse"].firstMatch, "Matchday v2", timeout: 60)
        XCTAssertTrue(app.buttons["Pulse"].firstMatch.isSelected, "Pulse is the first tab")
        waitFor(app.staticTexts["What matters now"].firstMatch, "Pulse", timeout: 30)
        settle()
        check(app, "90-matchday-pulse")
        let rival = app.staticTexts["Your rival"].firstMatch
        if rival.waitForExistence(timeout: 20) {
            reveal(rival, in: app)
            settle()
            check(app, "90b-matchday-pulse-rival")
            // Phase 1: the live head-to-head.
            let headToHead = app.buttons["Open head-to-head"].firstMatch
            reveal(headToHead, in: app)
            headToHead.tap()
            waitFor(app.navigationBars.matching(NSPredicate(format: "identifier BEGINSWITH 'You v '")).firstMatch,
                    "Head-to-head", timeout: 20)
            settle()
            check(app, "90c-matchday-head-to-head")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            settle()
        }
        // Phase 3: your leagues, live (not in replays, so only when the server sends them).
        let leagues = app.staticTexts["Your leagues, live"].firstMatch
        if leagues.waitForExistence(timeout: 3) {
            reveal(leagues, in: app)
            settle()
            check(app, "90f-matchday-leagues-live")
        }
        // Phase 2: a moment from Just happened, then the pitch and Matches.
        for _ in 0..<6 { app.swipeDown() }
        let moment = app.buttons.matching(NSPredicate(format: "label CONTAINS ' scores' OR label CONTAINS ' assists'")).firstMatch
        if moment.waitForExistence(timeout: 5) {
            reveal(moment, in: app)
            settle() // let the scroll come to rest, or the tap lands on whatever moves under it
            moment.tap()
            if app.navigationBars["Moment"].firstMatch.waitForExistence(timeout: 15) {
                settle()
                check(app, "90e-matchday-moment")
                app.navigationBars.buttons.element(boundBy: 0).tap()
                settle()
            }
        }
        for _ in 0..<6 { app.swipeDown() }
        app.buttons["Your team"].firstMatch.tap()
        if app.buttons["Pitch"].firstMatch.waitForExistence(timeout: 10) {
            app.buttons["Pitch"].firstMatch.tap()
            settle()
            // Like the Planner's pitch: each tile is one element, its text sized to fit five across.
            check(app, "90f-matchday-pitch", combinedTiles: true)
        }
        app.buttons["Matches"].firstMatch.tap()
        settle()
        check(app, "90g-matchday-matches")
        app.buttons["Pulse"].firstMatch.tap()
        settle()

        // Phase 1: every point within reach, when there are more than Pulse shows.
        let all = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'All points within reach'")).firstMatch
        for _ in 0..<6 { app.swipeDown() }
        if all.waitForExistence(timeout: 3) {
            reveal(all, in: app)
            all.tap()
            waitFor(app.navigationBars["Next points"].firstMatch, "Next points")
            settle()
            check(app, "90d-matchday-next-points")
        }
    }

    func test22Rivals() {
        let app = launch(["-entryId", team])
        // Rivals come from saved leagues; test10 removes League of Experts when it's done.
        openMyTeam(app)
        let leaguesButton = app.buttons["Your leagues"].firstMatch
        waitFor(leaguesButton, "Your leagues button", timeout: 40)
        leaguesButton.tap()
        let addLeague = app.buttons["Add a league"].firstMatch
        waitFor(addLeague, "Your leagues", timeout: 40)
        waitFor(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Elite 100'")).firstMatch, "Elite 100", timeout: 40)
        let league = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'LEAGUE OF EXPERTS'")).firstMatch
        if !league.exists {
            addLeague.tap()
            let field = app.textFields["Mini-league ID"].firstMatch
            waitFor(field, "Add a league")
            field.tap()
            field.typeText("783382")
            app.buttons["Add"].firstMatch.tap()
            waitFor(league, "League added", timeout: 120)
        }

        app.tabBars.buttons["Watch"].tap()
        let rivalsTab = app.segmentedControls.buttons["Rivals"].firstMatch
        waitFor(rivalsTab, "Watch")
        rivalsTab.tap()
        let add = app.buttons.matching(NSPredicate(format: "label == 'Add a rival' OR label == 'Add'")).firstMatch
        waitFor(add, "Rivals", timeout: 60)
        add.tap()
        let field = app.searchFields.firstMatch
        waitFor(field, "Add a rival", timeout: 60)
        field.tap()
        field.typeText("McBride")
        let addAndy = app.buttons["Add Andy McBride as a rival"].firstMatch
        if addAndy.waitForExistence(timeout: 20) {
            addAndy.tap()
            let feature = app.alerts.buttons["Feature"].firstMatch
            if feature.waitForExistence(timeout: 20) { feature.tap() }
        }
        settle()
        check(app, "84-rivals-add", sizesAndLists: false)
        // While searching, the search's close button stands in for Done.
        let closeSearch = app.buttons.matching(NSPredicate(format: "label == 'Cancel' OR label == 'Close'")).firstMatch
        if closeSearch.exists { closeSearch.tap() }
        let done = app.buttons["Done"].firstMatch
        waitFor(done, "Add a rival's Done")
        done.tap()

        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Andy'")).firstMatch
        waitFor(row, "Your rivals", timeout: 60)
        settle()
        check(app, "85-rivals")
        row.tap()
        waitFor(app.buttons["Overview"].firstMatch, "Rival", timeout: 60)
        settle()
        check(app, "86-rival-overview")
        app.buttons["Teams"].firstMatch.tap()
        settle()
        check(app, "87-rival-teams")
        app.buttons["Stats"].firstMatch.tap()
        settle()
        check(app, "88-rival-stats")
        // GW Audit: every gameweek (happy-backend-pal#71).
        app.buttons["GW Audit"].firstMatch.tap()
        settle()
        check(app, "88b-rival-audit")

        // Today: the featured rival under your leagues.
        app.tabBars.buttons["Today"].tap()
        let featured = app.staticTexts["Your rival"].firstMatch
        waitFor(app.staticTexts["Your leagues"].firstMatch, "Today", timeout: 60)
        reveal(featured, in: app)
        settle()
        check(app, "89-today-rival")
    }

    func test20Odds() {
        var arguments = ["-entryId", team]
        let base = setting("auditApiBaseURL", default: "")
        if !base.isEmpty { arguments += ["-apiBaseURL", base] }
        let app = launch(arguments)
        openMyTeam(app)
        app.buttons["Pitch"].firstMatch.tap()
        let menu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Show on tiles'")).firstMatch
        waitFor(menu, "Show on tiles", timeout: 60)
        menu.tap()
        let odds = app.buttons["Odds"].firstMatch
        waitFor(odds, "Odds layer")
        odds.tap()
        waitFor(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'clean sheet' OR label CONTAINS[c] 'to score'")).firstMatch,
                "Odds on the tiles")
        settle()
        check(app, "78-team-odds", combinedTiles: true, clippingCheckedLarge: true)
        menu.tap()
        let oddsCheck = app.buttons["Odds check"].firstMatch
        waitFor(oddsCheck, "Odds check in the menu")
        oddsCheck.tap()
        waitFor(app.staticTexts.matching(NSPredicate(format: "label ==[c] 'Captain options'")).firstMatch, "Odds check", timeout: 30)
        settle()
        check(app, "79-odds-check")
        app.buttons["Done"].tap()
    }

    func test07ExploreWithoutATeam() {
        let app = launch(["-entryId", "0", "-exploring", "YES"])
        waitFor(app.buttons["Add my FPL team"].firstMatch, "Explore Today")
        check(app, "09-explore-today")
        openMyTeam(app)
        reveal(app.staticTexts["Add your FPL team"].firstMatch, in: app)
        waitFor(app.staticTexts["Add your FPL team"].firstMatch, "Explore Team")
        // The Planner's start card, or the plan switcher (a sheet) when the device has plans.
        check(app, "10-explore-team", sizesAndLists: false)
    }
}
