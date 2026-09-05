import SwiftUI

/// Editor for user-defined routing rules (domain / IP → proxy, direct, block).
struct RulesView: View {
    @EnvironmentObject private var vpn: VPNManager
    @Environment(\.presentationMode) private var presentation
    @State private var newPattern = ""
    @State private var newAction: RuleAction = .direct

    private var trimmed: String { newPattern.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ZStack {
            Sky.ground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ScreenHeader(back: "Settings", title: "Routing rules",
                                 subtitle: "Send a domain or IP range through the server, straight out, or nowhere. Rules are checked top to bottom, before the routing mode.") {
                        presentation.wrappedValue.dismiss()
                    }
                    addRule
                    SectionHeader(title: "Rules", trailing: vpn.settings.customRules.isEmpty ? nil : "\(vpn.settings.customRules.count)")
                    if vpn.settings.customRules.isEmpty {
                        Footnote("No custom rules.")
                    } else {
                        ForEach(Array(vpn.settings.customRules.enumerated()), id: \.element.id) { index, rule in
                            ruleRow(rule, index: index)
                            Rule(strong: false)
                        }
                    }
                }
                .padding(.bottom, 40)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
        }
        .navigationBarHidden(true)
    }

    private var addRule: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Add rule")
            VStack(alignment: .leading, spacing: 12) {
                BoxedField(label: "Pattern") {
                    TextField("domain:example.com or 1.2.3.0/24", text: $newPattern)
                        .font(Sky.mono(13)).foregroundColor(Sky.ink)
                        .keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
                        .onSubmit(add)
                }
                Kicker(text: "Action").padding(.top, 4)
                Segmented(options: [("Proxy", RuleAction.proxy), ("Direct", .direct), ("Block", .block)], selection: $newAction)
                Button(action: add) {
                    HStack { Text("Add"); Spacer(); Image(systemName: "plus").font(.system(size: 16, weight: .bold)) }
                }
                .buttonStyle(PrimaryButtonStyle(height: 48))
                .disabled(trimmed.isEmpty)
                .padding(.top, 8)
            }
            .padding(.horizontal, 24).padding(.vertical, 20)
            Rule()
            Footnote("Examples: domain:instagram.com, full:api.telegram.org, keyword:youtube, geosite:cn, 1.2.3.0/24, geoip:cn.")
        }
    }

    private func ruleRow(_ rule: RoutingRule, index: Int) -> some View {
        let binding = Binding<Bool>(
            get: { vpn.settings.customRules.first { $0.id == rule.id }?.enabled ?? false },
            set: { on in if let i = vpn.settings.customRules.firstIndex(where: { $0.id == rule.id }) { vpn.settings.customRules[i].enabled = on } }
        )
        return HStack(alignment: .center, spacing: 14) {
            Rectangle().fill(color(rule.action).opacity(rule.enabled ? 1 : 0.3)).frame(width: 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: rule.pattern).font(Sky.mono(13, medium: true)).foregroundColor(Sky.ink).lineLimit(1)
                Text(actionLabel(rule.action)).font(Sky.body(12.5)).foregroundColor(Sky.muted(0.6))
            }
            Spacer()
            Toggle(isOn: binding) { EmptyView() }.toggleStyle(SquareToggleStyle()).fixedSize()
            Menu {
                Button { move(rule, by: -1) } label: { Label("Move up", systemImage: "arrow.up") }.disabled(index == 0)
                Button { move(rule, by: 1) } label: { Label("Move down", systemImage: "arrow.down") }.disabled(index == vpn.settings.customRules.count - 1)
                Button(role: .destructive) { vpn.settings.customRules.removeAll { $0.id == rule.id } } label: { Label("Delete", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 14, weight: .heavy)).foregroundColor(Sky.ink)
                    .frame(width: 30, height: 30).overlay(Rectangle().stroke(Sky.divider(), lineWidth: 1))
            }
        }
        .padding(.vertical, 14).padding(.horizontal, 24)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func add() {
        guard !trimmed.isEmpty else { return }
        vpn.settings.customRules.append(RoutingRule(pattern: trimmed, action: newAction))
        newPattern = ""
    }

    private func move(_ rule: RoutingRule, by delta: Int) {
        guard let i = vpn.settings.customRules.firstIndex(where: { $0.id == rule.id }) else { return }
        let j = i + delta
        guard vpn.settings.customRules.indices.contains(j) else { return }
        vpn.settings.customRules.swapAt(i, j)
    }

    private func color(_ a: RuleAction) -> Color {
        switch a {
        case .proxy: return Sky.primary
        case .direct: return Sky.ink
        case .block: return Sky.accent
        }
    }

    private func actionLabel(_ a: RuleAction) -> String {
        switch a {
        case .proxy: return String(localized: "Proxy")
        case .direct: return String(localized: "Direct")
        case .block: return String(localized: "Block")
        }
    }
}
