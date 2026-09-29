import XCTest

/// One tap on Connect, the way a customer does it, and what the screen shows each second after:
/// the connecting screen's percentage, the connection state and the ad. The app's own log
/// (Documents/debug.log and tunnel.log) tells what happened underneath.
final class TapConnectTests: XCTestCase {
    private let app = XCUIApplication()

    func testTapConnectOnce() throws {
        app.launch()
        let connect = app.buttons["connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 30), "no Connect button")
        if app.staticTexts["Connected"].exists {
            connect.tap()
            _ = app.staticTexts["Not connected"].waitForExistence(timeout: 20)
            sleep(2)
        }
        connect.tap()
        for step in 1...12 {
            usleep(500_000)
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = String(format: "t%04.1fs", Double(step) * 0.5)
            shot.lifetime = .keepAlways
            add(shot)
            let percent = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH '%%'")).firstMatch
            print("[ui] t=\(Double(step) * 0.5)s percent=\(percent.exists ? percent.label : "-") connected=\(app.staticTexts["Connected"].exists)")
        }
        sleep(20)
    }

    /// Two quick taps on Connect, as an impatient customer does: the connection must come up and
    /// stay up (the second tap used to stop the first one's tunnel a second after it started).
    func testDoubleTapStaysConnected() throws {
        app.launch()
        let connect = app.buttons["connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 30), "no Connect button")
        if app.staticTexts["Connected"].exists {
            connect.tap()
            _ = app.staticTexts["Not connected"].waitForExistence(timeout: 20)
            sleep(2)
        }
        connect.tap()
        usleep(300_000)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()   // where the button was
        sleep(40)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "after 40 s"
        shot.lifetime = .keepAlways
        add(shot)
        print("[ui] after 40 s: connected=\(app.staticTexts["Connected"].exists) notConnected=\(app.staticTexts["Not connected"].exists)")
    }

    /// Connect, the ad, close it, disconnect, connect again: the second connect falls in the
    /// 20-minute gap, so the connecting screen must close quickly and the tunnel stay up.
    func testSecondConnectInCooldown() throws {
        app.launch()
        let connect = app.buttons["connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 30), "no Connect button")
        if app.staticTexts["Connected"].exists {
            connect.tap()
            _ = app.staticTexts["Not connected"].waitForExistence(timeout: 20)
            sleep(2)
        }
        connect.tap()
        sleep(35)   // the ad plays; the test ad grants its reward after a few seconds
        let shot0 = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot0.name = "ad up"
        shot0.lifetime = .keepAlways
        add(shot0)
        for line in app.debugDescription.split(separator: "\n") where line.contains("Button") || line.localizedCaseInsensitiveContains("close") {
            print("[ui] ad: \(line.trimmingCharacters(in: .whitespaces).prefix(160))")
        }
        let close = app.buttons.matching(NSPredicate(format: "label == 'Close' AND enabled == true")).firstMatch
        if close.exists { close.tap() } else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.08)).tap() }
        sleep(4)
        XCTAssertTrue(connect.waitForExistence(timeout: 10), "the ad did not close")
        connect.tap()   // disconnect
        _ = app.staticTexts["Not connected"].waitForExistence(timeout: 20)
        sleep(2)
        connect.tap()   // connect again, inside the 20 minutes
        for step in [1, 3, 6, 10] {
            sleep(step == 1 ? 1 : UInt32(step - [1, 3, 6, 10][max(0, [1, 3, 6, 10].firstIndex(of: step)! - 1)]))
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "second connect \(step)s"
            shot.lifetime = .keepAlways
            add(shot)
        }
        print("[ui] second connect: connected=\(app.staticTexts["Connected"].exists)")
    }

    /// What is on screen right now, without launching anew: a picture and the buttons it has.
    func testLookAtScreen() throws {
        let running = XCUIApplication()
        running.activate()
        sleep(1)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "now"
        shot.lifetime = .keepAlways
        add(shot)
        for b in running.buttons.allElementsBoundByIndex.prefix(20) {
            print("[ui] button id=\(b.identifier) label=\(b.label) frame=\(b.frame)")
        }
    }

    /// With a consent message set up in AdMob and a European exit, Google's consent form comes
    /// first; after "Consent" the ad follows.
    func testConsentFormThenAd() throws {
        app.launch()
        let connect = app.buttons["connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 30), "no Connect button")
        if app.staticTexts["Connected"].exists {
            connect.tap()
            _ = app.staticTexts["Not connected"].waitForExistence(timeout: 20)
            sleep(2)
        }
        connect.tap()
        let consent = app.buttons["Consent"]
        let formShown = consent.waitForExistence(timeout: 40)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = formShown ? "consent form" : "no consent form"
        shot.lifetime = .keepAlways
        add(shot)
        print("[ui] consent form shown: \(formShown)")
        if formShown {
            consent.tap()
            // The tracking prompt, if it comes, is answered by the system alert handler below.
            addUIInterruptionMonitor(withDescription: "tracking") { alert in
                for label in ["Ask App Not to Track", "Allow"] where alert.buttons[label].exists {
                    alert.buttons[label].tap(); return true
                }
                return false
            }
            app.tap()
        }
        sleep(25)
        let after = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        after.name = "25 s after"
        after.lifetime = .keepAlways
        add(after)
    }
}
