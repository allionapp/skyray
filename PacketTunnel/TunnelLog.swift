import Foundation
import os

/// Appends log lines to a file in the App Group so the app can display them.
enum TunnelLog {
    private static let logger = Logger(subsystem: AppConstants.tunnelBundleId, category: "tunnel")
    private static let queue = DispatchQueue(label: "tunnel.log")
    private static let maxBytes = 512 * 1024

    static func clear() {
        queue.async { try? FileManager.default.removeItem(at: ProfileStore.shared.tunnelLogURL) }
    }

    static func write(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(stamp)] \(message)\n"
        queue.async {
            let url = ProfileStore.shared.tunnelLogURL
            if let handle = try? FileHandle(forWritingTo: url) {
                let size = (try? handle.seekToEnd()) ?? 0
                if size > maxBytes { try? handle.truncate(atOffset: 0) }
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}
