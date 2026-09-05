import Foundation
import NetworkExtension

#if canImport(AppIntents)
import AppIntents

/// Siri / Shortcuts: "Connect SkyRay", "Disconnect SkyRay", "Toggle SkyRay".
@available(iOS 16.0, *)
struct ConnectVPNIntent: AppIntent {
    static var title: LocalizedStringResource = "Connect SkyRay"
    static var description = IntentDescription("Connects the VPN using the selected server.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        try await VPNIntentHelper.setConnected(true)
        return .result()
    }
}

@available(iOS 16.0, *)
struct DisconnectVPNIntent: AppIntent {
    static var title: LocalizedStringResource = "Disconnect SkyRay"
    static var description = IntentDescription("Disconnects the VPN.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        try await VPNIntentHelper.setConnected(false)
        return .result()
    }
}

@available(iOS 16.0, *)
struct ToggleVPNIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle SkyRay"
    static var description = IntentDescription("Connects or disconnects the VPN.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        let connected = managers.first?.connection.status == .connected
        try await VPNIntentHelper.setConnected(!connected)
        return .result()
    }
}

@available(iOS 16.0, *)
struct SkyRayShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ConnectVPNIntent(), phrases: ["Connect \(.applicationName)", "Turn on \(.applicationName)"],
                    shortTitle: "Connect", systemImageName: "power")
        AppShortcut(intent: DisconnectVPNIntent(), phrases: ["Disconnect \(.applicationName)", "Turn off \(.applicationName)"],
                    shortTitle: "Disconnect", systemImageName: "power.circle")
    }
}
#endif

enum VPNIntentHelper {
    static func setConnected(_ connected: Bool) async throws {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        guard let manager = managers.first(where: {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == AppConstants.tunnelBundleId
        }) ?? managers.first else {
            throw NSError(domain: "SkyRay", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Open SkyRay and connect once first.")])
        }
        if connected {
            guard ProfileStore.shared.readActiveProfile() != nil else {
                throw NSError(domain: "SkyRay", code: 2, userInfo: [NSLocalizedDescriptionKey: String(localized: "Add and select a server first.")])
            }
            try manager.connection.startVPNTunnel()
        } else {
            manager.connection.stopVPNTunnel()
        }
    }
}
