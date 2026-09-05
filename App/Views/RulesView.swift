import SwiftUI

/// Editor for user-defined routing rules (domain / IP → proxy, direct, block).
struct RulesView: View {
    @EnvironmentObject private var vpn: VPNManager
    @State private var newPattern = ""
    @State private var newAction: RuleAction = .direct

    var body: some View {
        List {
            Section(header: Text("Add rule"), footer: Text("Examples: domain:instagram.com, full:api.telegram.org, keyword:youtube, geosite:cn, 1.2.3.0/24, geoip:cn. Rules are checked top to bottom before the routing mode.")) {
                TextField("domain:example.com or 1.2.3.0/24", text: $newPattern)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Picker("Action", selection: $newAction) {
                    Text("Proxy").tag(RuleAction.proxy)
                    Text("Direct").tag(RuleAction.direct)
                    Text("Block").tag(RuleAction.block)
                }
                .pickerStyle(.segmented)
                Button {
                    let p = newPattern.trimmingCharacters(in: .whitespaces)
                    guard !p.isEmpty else { return }
                    vpn.settings.customRules.append(RoutingRule(pattern: p, action: newAction))
                    newPattern = ""
                } label: { Label("Add", systemImage: "plus") }
                .disabled(newPattern.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Section(header: Text("Rules")) {
                if vpn.settings.customRules.isEmpty {
                    Text("No custom rules.").foregroundColor(.secondary)
                }
                ForEach($vpn.settings.customRules) { $rule in
                    HStack {
                        Toggle(isOn: $rule.enabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.pattern).font(.body.monospaced()).lineLimit(1)
                                Text(actionLabel(rule.action)).font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .onDelete { vpn.settings.customRules.remove(atOffsets: $0) }
                .onMove { vpn.settings.customRules.move(fromOffsets: $0, toOffset: $1) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Routing rules")
        .toolbar { EditButton() }
    }

    private func actionLabel(_ a: RuleAction) -> String {
        switch a {
        case .proxy: return String(localized: "Proxy")
        case .direct: return String(localized: "Direct")
        case .block: return String(localized: "Block")
        }
    }
}
