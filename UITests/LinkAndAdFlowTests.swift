import XCTest

/// Drives SkyRay on a real phone the way a customer would, for what only a real tunnel shows:
/// switching links, the server menu right after a switch, connecting, and the ad that follows.
/// What it sees is printed and attached as screenshots; the app's own log (the ad signals at
/// each request) lands in Documents/debug.log of a development build.
final class LinkAndAdFlowTests: XCTestCase {
    private let app = XCUIApplication()

    func testSwitchLinksServerMenuConnectAndAd() throws {
        app.launch()
        let name = app.buttons["linkName"]
        XCTAssertTrue(name.waitForExistence(timeout: 30), "Home did not show a link")
        shot("1 home")
        let start = name.label

        // Every other link in turn, then back: the server menu is opened straight after each
        // switch, without Test again. The app logs each link's first servers to compare with.
        for link in linkNames() where link != start {
            _ = try switchLink(to: link)
            print("[ui] server menu right after switching to \(link): \(serverMenuItems().prefix(4))")
            shot("menu after switching to \(link)")
            dismissMenu()
        }
        _ = try switchLink(to: start)
        print("[ui] server menu right after switching back to \(start): \(serverMenuItems().prefix(4))")
        shot("menu after switching back")
        dismissMenu()

        // Connect through a link whose servers answer (sifaro, Germany, when it is there).
        if let working = linkNames().first(where: { $0.lowercased() == "sifaro" }) {
            _ = try switchLink(to: working)
        }

        // Connected already? Reconnect, so this run has a fresh connect and its ad.
        let connect = app.buttons["connect"]
        if app.staticTexts["Connected"].exists {
            connect.tap()
            _ = app.staticTexts["Not connected"].waitForExistence(timeout: 20)
        }
        connect.tap()
        XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 90) || adIsUp(), "did not connect")
        shot("4 connected")

        // The ad: watch it to the end, then close it.
        waitForAdAndClose()
        shot("5 after the ad")
        // Leave time for the exit probe and the next ad request.
        sleep(20)
        shot("6 settled")
    }

    /// Straight after launch, and straight after Refresh, the server menu must already list the
    /// link's servers: no Test again first.
    func testServerMenuWithoutTestAgain() throws {
        app.launch()
        XCTAssertTrue(app.buttons["linkName"].waitForExistence(timeout: 30), "Home did not show a link")
        print("[ui] launch: label \(app.buttons["serverMenu"].label)")
        let atLaunch = serverMenuItems()
        print("[ui] menu at launch: \(atLaunch.count) items \(atLaunch.prefix(4))")
        shot("menu at launch")
        dismissMenu()

        let refresh = app.buttons["Refresh"]
        if refresh.exists {
            refresh.tap()
            sleep(12)
            print("[ui] after Refresh: label \(app.buttons["serverMenu"].label)")
            let afterRefresh = serverMenuItems()
            print("[ui] menu after Refresh: \(afterRefresh.count) items \(afterRefresh.prefix(4))")
            shot("menu after refresh")
            dismissMenu()
        }
        XCTAssertGreaterThan(atLaunch.count, 1, "the server menu had no servers at launch")
    }

    // MARK: Steps

    /// Opens "Your links" and taps a link: [to] by name, or else the first one not in use.
    @discardableResult
    private func switchLink(to target: String? = nil, awayFrom: Bool = false) throws -> String {
        app.buttons["linkName"].tap()
        let sheet = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app
        _ = sheet.buttons.firstMatch.waitForExistence(timeout: 10)
        let skip = ["Cancel", "+ Add another link", "Remove this link"]
        let choices = sheet.buttons.allElementsBoundByIndex.map(\.label).filter { !skip.contains($0) && !$0.isEmpty }
        print("[ui] your links: \(choices)")
        let pick: String?
        if let target {
            pick = choices.first { $0 == target || $0 == "✓ " + target }
        } else {
            pick = choices.first { !$0.hasPrefix("✓") }
        }
        guard let pick else { throw XCTSkip("no link to switch to among \(choices)") }
        sheet.buttons[pick].tap()
        sleep(3)
        return pick.replacingOccurrences(of: "✓ ", with: "")
    }

    private func serverMenuItems() -> [String] {
        app.buttons["serverMenu"].tap()
        sleep(2)
        let skip: Set<String> = ["serverMenu", "connect", "linkName"]
        return app.buttons.allElementsBoundByIndex
            .filter { $0.isHittable && !skip.contains($0.identifier) }
            .map(\.label)
            .filter { $0.contains("·") || $0.contains("Auto") }
    }

    /// The links as "Your links" lists them, without the ✓.
    private func linkNames() -> [String] {
        app.buttons["linkName"].tap()
        let sheet = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app
        _ = sheet.buttons.firstMatch.waitForExistence(timeout: 10)
        let skip = ["Cancel", "+ Add another link", "Remove this link"]
        let names = sheet.buttons.allElementsBoundByIndex.map(\.label)
            .filter { !skip.contains($0) && !$0.isEmpty }
            .map { $0.replacingOccurrences(of: "✓ ", with: "") }
        dismissMenu()   // the dialog closes the same way: a tap outside it
        return names
    }

    private func dismissMenu() {
        let region = app.otherElements["PopoverDismissRegion"]
        if region.exists {
            region.tap()
        } else {
            app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.97)).tap()
        }
        sleep(1)
    }

    private func adIsUp() -> Bool {
        app.staticTexts["Test Ad"].exists || app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'close'")).count > 0
    }

    /// Waits for the reward (the test ad says so), then closes the ad; never closes it earlier.
    private func waitForAdAndClose() {
        let deadline = Date().addingTimeInterval(120)
        var sawAd = false
        while Date() < deadline {
            if adIsUp() { sawAd = true }
            let rewarded = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'reward granted'")).count > 0
            let close = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'close'")).firstMatch
            if sawAd, rewarded, close.exists, close.isHittable {
                shot("ad rewarded")
                close.tap()
                print("[ui] ad closed after the reward")
                return
            }
            if sawAd, Int(Date().timeIntervalSince1970) % 10 < 2 {
                shot("ad \(Int(deadline.timeIntervalSinceNow))s left")
                print("[ui] ad buttons: \(app.buttons.allElementsBoundByIndex.map(\.label)) texts: \(app.staticTexts.allElementsBoundByIndex.prefix(8).map(\.label))")
            }
            if sawAd, !adIsUp(), app.buttons["connect"].exists {
                print("[ui] the ad closed by itself")
                return
            }
            sleep(2)
        }
        print("[ui] ad seen: \(sawAd); not closed within the wait")
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
