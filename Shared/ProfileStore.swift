import Foundation

/// Persists profiles and settings in the App Group container so that both the
/// app and the tunnel extension can read them. Falls back to the Documents
/// directory when the container is unavailable (unsigned simulator builds).
final class ProfileStore {
    static let shared = ProfileStore()

    let containerURL: URL
    let defaults: UserDefaults

    private init() {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroup) {
            containerURL = url
        } else {
            containerURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }
        defaults = UserDefaults(suiteName: AppConstants.appGroup) ?? .standard
    }

    private func url(_ name: String) -> URL { containerURL.appendingPathComponent(name) }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    // MARK: - Profiles

    /// Decodes each profile individually so one bad entry (for example after an
    /// app update changed the format) never wipes the whole list. Falls back to
    /// the backup file when the main file is unreadable.
    func loadProfiles() -> [ServerProfile] {
        if let list = decodeProfiles(at: url(AppConstants.profilesFile)) { return list }
        if let list = decodeProfiles(at: url(AppConstants.profilesBackupFile)) { return list }
        return []
    }

    private func decodeProfiles(at fileURL: URL) -> [ServerProfile]? {
        guard let data = try? Data(contentsOf: fileURL),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return nil }
        var result: [ServerProfile] = []
        for item in raw {
            guard let itemData = try? JSONSerialization.data(withJSONObject: item),
                  let profile = try? Self.decoder.decode(ServerProfile.self, from: itemData) else { continue }
            result.append(profile)
        }
        return result
    }

    func saveProfiles(_ profiles: [ServerProfile]) {
        guard let data = try? Self.encoder.encode(profiles) else { return }
        let main = url(AppConstants.profilesFile)
        let backup = url(AppConstants.profilesBackupFile)
        if FileManager.default.fileExists(atPath: main.path) {
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: main, to: backup)
        }
        try? data.write(to: main, options: .atomic)
    }

    var selectedProfileId: UUID? {
        get { defaults.string(forKey: AppConstants.selectedProfileKey).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: AppConstants.selectedProfileKey) }
    }

    /// Kept out of AppSettings: its synthesized decoding would drop every
    /// stored setting on a build that adds a field. Absent means automatic.
    var automaticSelection: Bool {
        get { defaults.object(forKey: AppConstants.automaticSelectionKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: AppConstants.automaticSelectionKey) }
    }

    // MARK: - Active profile (what the extension actually reads)

    func writeActiveProfile(_ profile: ServerProfile) {
        guard let data = try? Self.encoder.encode(profile) else { return }
        try? data.write(to: url(AppConstants.activeProfileFile), options: .atomic)
    }

    func readActiveProfile() -> ServerProfile? {
        guard let data = try? Data(contentsOf: url(AppConstants.activeProfileFile)) else { return nil }
        return try? Self.decoder.decode(ServerProfile.self, from: data)
    }

    // MARK: - Settings

    func loadSettings() -> AppSettings {
        guard let data = try? Data(contentsOf: url(AppConstants.settingsFile)),
              let settings = try? Self.decoder.decode(AppSettings.self, from: data) else { return AppSettings() }
        return settings
    }

    func saveSettings(_ settings: AppSettings) {
        guard let data = try? Self.encoder.encode(settings) else { return }
        try? data.write(to: url(AppConstants.settingsFile), options: .atomic)
    }

    // MARK: - Subscriptions

    func loadSubscriptions() -> [SubscriptionInfo] {
        guard let data = try? Data(contentsOf: url(AppConstants.subscriptionsInfoFile)),
              let list = try? Self.decoder.decode([SubscriptionInfo].self, from: data) else { return [] }
        return list
    }

    func saveSubscriptions(_ list: [SubscriptionInfo]) {
        guard let data = try? Self.encoder.encode(list) else { return }
        try? data.write(to: url(AppConstants.subscriptionsInfoFile), options: .atomic)
    }

    // MARK: - Tunnel log (written by the extension, read by the app)

    var tunnelLogURL: URL { url(AppConstants.tunnelLogFile) }

    /// Appends one line to the same log the tunnel writes, so events that only
    /// the app can see (the ad, mainly) sit in order with the tunnel's own.
    func appendTunnelLine(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        if let handle = try? FileHandle(forWritingTo: tunnelLogURL) {
            _ = try? handle.seekToEnd()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: tunnelLogURL)
        }
    }

    func readTunnelLog() -> String {
        (try? String(contentsOf: tunnelLogURL, encoding: .utf8)) ?? ""
    }
}
