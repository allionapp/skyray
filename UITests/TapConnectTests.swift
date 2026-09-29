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
}
