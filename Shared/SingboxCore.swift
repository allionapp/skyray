import Foundation
import LibXray

/// Swift wrapper over the sing-box functions exported by the raycore Go package
/// (bundled in the same framework as libXray). gomobile exports them as C
/// functions with an NSError out-parameter, so errors are bridged by hand.
enum SingboxCore {
    static func version() -> String { RaycoreSingboxVersion() }

    static func run(_ configJSON: String) throws {
        var error: NSError?
        if !RaycoreSingboxStart(configJSON, &error) { throw error ?? XrayCoreError.invoke("sing-box failed to start") }
    }

    static func stop() throws {
        var error: NSError?
        if !RaycoreSingboxStop(&error) { throw error ?? XrayCoreError.invoke("sing-box failed to stop") }
    }

    static func isRunning() -> Bool { RaycoreSingboxRunning() }

    static func testConfig(_ configJSON: String) throws {
        var error: NSError?
        if !RaycoreSingboxTest(configJSON, &error) { throw error ?? XrayCoreError.invoke("Invalid sing-box configuration") }
    }

    /// Real HTTP round trip through one outbound (JSON of a single sing-box outbound).
    static func ping(outboundJSON: String,
                     timeoutSeconds: Int = AppConstants.pingTimeoutSeconds,
                     url: String = AppConstants.pingURLPlain) -> PingResult {
        var delay: Int64 = 0
        var error: NSError?
        if RaycoreSingboxPing(outboundJSON, url, timeoutSeconds * 1000, &delay, &error) {
            return PingResult(success: true, delayMs: Int(delay), error: "")
        }
        return PingResult(success: false, delayMs: -1, error: error?.localizedDescription ?? "ping failed")
    }
}
