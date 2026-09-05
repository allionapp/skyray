import SwiftUI

/// Modernist theme from the SkyRay design: flat, square, ink on a warm light
/// ground, 2px rules, Archivo for text and IBM Plex Mono for data.
enum Sky {
    // MARK: Colors (light ground; dark variants adapt automatically)
    static let ground = Color("SkyGround", bundle: nil, light: 0xF3F2F2, dark: 0x201E1D)
    static let surface = Color("SkySurface", bundle: nil, light: 0xEAE9E9, dark: 0x2D2B2B)
    static let ink = Color("SkyInk", bundle: nil, light: 0x201E1D, dark: 0xF3F2F2)
    static let paper = Color("SkyPaper", bundle: nil, light: 0xFFFFFF, dark: 0x171514)
    /// The one red field: connected state and small emphasis.
    static let accent = Color(hex: 0xEC3013)
    static let accentDeep = Color(hex: 0xAE1800)
    static let accentTint = Color(hex: 0xFFE0D9)
    static let accentTintInk = Color(hex: 0x7C1405)
    /// Primary actions (Connect, Check this link, Add subscription).
    static let primary = Color(hex: 0x8013EC)
    static let onField = Color(hex: 0xF3F2F2)
    static let fieldInk = Color(hex: 0x201E1D)

    static func divider(_ strong: Bool = true) -> Color { ink.opacity(strong ? 0.4 : 0.18) }
    static func muted(_ level: Double = 0.6) -> Color { ink.opacity(level) }

    // MARK: Type
    static func heading(_ size: CGFloat) -> Font { .custom("ArchivoRoman-ExtraBold", size: size) }
    static func semibold(_ size: CGFloat) -> Font { .custom("Archivo-SemiBold", size: size) }
    static func body(_ size: CGFloat) -> Font { .custom("ArchivoRoman-Regular", size: size) }
    static func mono(_ size: CGFloat, medium: Bool = false) -> Font {
        .custom(medium ? "IBMPlexMono-Medium" : "IBMPlexMono-Regular", size: size)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: opacity)
    }
    /// Light/dark adaptive color without an asset catalog entry.
    init(_ name: String, bundle: Bundle?, light: UInt32, dark: UInt32) {
        self.init(UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                           blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        })
    }
}

// MARK: - Rules

/// A 2px (strong) or 1px (light) horizontal rule.
struct Rule: View {
    var strong = true
    var onField = false
    var body: some View {
        Rectangle()
            .fill(onField ? Sky.onField.opacity(0.55) : Sky.divider(strong))
            .frame(height: strong ? 2 : 1)
    }
}

/// Small uppercase label with wide tracking ("STEP 1 OF 2", "SELECTED SERVER").
struct Kicker: View {
    let text: LocalizedStringKey
    var color: Color = Sky.muted(0.5)
    var body: some View {
        Text(text)
            .font(Sky.semibold(11))
            .tracking(1.3)
            .textCase(.uppercase)
            .foregroundColor(color)
    }
}

// MARK: - Buttons

/// Solid purple action, label flush left, optional trailing icon.
struct PrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 54
    var fill: Color = Sky.primary
    var foreground: Color = Sky.onField
    var fullWidth = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Sky.heading(fullWidth ? 15 : 13))
            .foregroundColor(foreground)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height, maxHeight: height, alignment: .leading)
            .padding(.horizontal, fullWidth ? 18 : 14)
            .background(fill.opacity(configuration.isPressed ? 0.8 : 1))
            .contentShape(Rectangle())
    }
}

/// Outlined action, label flush left.
struct SecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 54
    var onField = false
    var fullWidth = true
    /// Text color override (e.g. `Sky.accentDeep` for destructive actions).
    var tint: Color? = nil
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Sky.heading(fullWidth ? 15 : 13))
            .foregroundColor(tint ?? (onField ? Sky.onField : Sky.ink))
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height, maxHeight: height, alignment: .leading)
            .padding(.horizontal, fullWidth ? 18 : 14)
            .background(
                (onField ? Sky.onField : Sky.ink).opacity(configuration.isPressed ? 0.12 : 0)
            )
            .overlay(Rectangle().stroke(onField ? Sky.onField.opacity(0.6) : Sky.divider(), lineWidth: 1))
            .contentShape(Rectangle())
    }
}

/// Small inline outlined button ("Change", "Edit", "Cancel").
struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Sky.heading(12))
            .foregroundColor(Sky.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Sky.ink.opacity(configuration.isPressed ? 0.12 : 0))
            .overlay(Rectangle().stroke(Sky.divider(), lineWidth: 1))
            .contentShape(Rectangle())
    }
}

/// "‹ Back" in the accent.
struct BackButton: View {
    let title: LocalizedStringKey
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.backward").font(.system(size: 12, weight: .heavy))
                Text(title).font(Sky.semibold(13))
            }
            .foregroundColor(Sky.accent)
        }
        .buttonStyle(.plain)
    }
}

/// Square toggle from the design (52×30, red when on).
struct SquareToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack {
                configuration.label
                Spacer()
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Rectangle().fill(configuration.isOn ? Sky.accent : Color(hex: 0xD7D3D3)).frame(width: 52, height: 30)
                    Rectangle().fill(Sky.onField).frame(width: 24, height: 24).padding(3)
                }
                .animation(.easeInOut(duration: 0.15), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The boxed text field with a kicker label ("CONFIG LINK").
struct BoxedField<Content: View>: View {
    let label: LocalizedStringKey
    var highlighted = false
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(Sky.semibold(10)).tracking(1).textCase(.uppercase).foregroundColor(Sky.muted(0.5))
            content()
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Sky.paper)
        .overlay(Rectangle().stroke(highlighted ? Sky.accent : Sky.divider(), lineWidth: 2))
    }
}

extension View {
    /// Pins content to the leading edge in both LTR and RTL layouts.
    func leading() -> some View { frame(maxWidth: .infinity, alignment: .leading) }
}


// MARK: - Settings building blocks

/// Square outlined icon button (36×36), e.g. the close "×" or a "…" menu anchor.
struct IconButton: View {
    let systemName: String
    var accessibility: LocalizedStringKey = ""
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName).font(.system(size: 15, weight: .heavy)).foregroundColor(Sky.ink)
                .frame(width: 36, height: 36)
                .overlay(Rectangle().stroke(Sky.divider(), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibility))
    }
}

/// Uppercase section title sitting on a strong rule.
struct SectionHeader: View {
    let title: LocalizedStringKey
    var trailing: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Kicker(text: title, color: Sky.muted(0.55))
                Spacer()
                if let trailing { Text(verbatim: trailing).font(Sky.mono(11, medium: true)).foregroundColor(Sky.muted(0.5)) }
            }
            .padding(.horizontal, 24).padding(.top, 30).padding(.bottom, 10)
            Rule()
        }
        .leading()
    }
}

/// Muted explanatory text under a group of rows.
struct Footnote: View {
    let content: Text
    init(_ key: LocalizedStringKey) { content = Text(key) }
    init(verbatim text: String) { content = Text(verbatim: text) }
    var body: some View {
        content.font(Sky.body(12.5)).foregroundColor(Sky.muted(0.6))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24).padding(.vertical, 14).leading()
    }
}

/// Title (+ optional detail) with the square toggle on the trailing edge.
struct ToggleRow: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey? = nil
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(Sky.semibold(15)).foregroundColor(Sky.ink)
                if let detail { Text(detail).font(Sky.body(12.5)).foregroundColor(Sky.muted(0.6)) }
            }
            .padding(.trailing, 12)
        }
        .toggleStyle(SquareToggleStyle())
        .padding(.horizontal, 24).padding(.vertical, 15)
    }
}

/// Label on the left, mono value on the right.
struct ValueRow: View {
    let title: LocalizedStringKey
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Sky.body(15)).foregroundColor(Sky.ink)
            Spacer(minLength: 16)
            Text(verbatim: value).font(Sky.mono(13)).foregroundColor(Sky.muted(0.65)).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 24).padding(.vertical, 15)
    }
}

/// Row that pushes another screen: title, optional mono detail, chevron.
struct NavRow<Destination: View>: View {
    let title: LocalizedStringKey
    var detail: String? = nil
    @ViewBuilder let destination: () -> Destination
    var body: some View {
        NavigationLink(destination: destination().navigationBarHidden(true)) {
            HStack {
                Text(title).font(Sky.semibold(15)).foregroundColor(Sky.ink)
                Spacer()
                if let detail { Text(verbatim: detail).font(Sky.mono(13)).foregroundColor(Sky.muted(0.55)) }
                Image(systemName: "chevron.forward").font(.system(size: 12, weight: .heavy)).foregroundColor(Sky.muted(0.45))
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Row that opens a web page in the browser.
struct LinkRow: View {
    let title: LocalizedStringKey
    let url: String
    var body: some View {
        if let target = URL(string: url) {
            Link(destination: target) {
                HStack {
                    Text(title).font(Sky.semibold(15)).foregroundColor(Sky.ink)
                    Spacer()
                    Image(systemName: "arrow.up.forward").font(.system(size: 12, weight: .heavy)).foregroundColor(Sky.accent)
                }
                .padding(.horizontal, 24).padding(.vertical, 16)
                .contentShape(Rectangle())
            }
        }
    }
}

/// Outlined segmented control; the chosen cell fills with ink.
struct Segmented<Value: Hashable>: View {
    let options: [(label: LocalizedStringKey, value: Value)]
    @Binding var selection: Value
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let selected = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.label).font(Sky.semibold(13)).lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundColor(selected ? Sky.ground : Sky.ink)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(selected ? Sky.ink : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < options.count - 1 { Rectangle().fill(Sky.divider()).frame(width: 1) }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay(Rectangle().stroke(Sky.divider(), lineWidth: 1))
        .animation(.easeInOut(duration: 0.12), value: selection)
    }
}

/// One choice in a vertical radio group (long labels that don't fit a segmented control).
struct RadioRow: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey? = nil
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle().stroke(selected ? Sky.accent : Sky.divider(), lineWidth: 1.5).frame(width: 18, height: 18)
                    if selected { Circle().fill(Sky.accent).frame(width: 9, height: 9) }
                }
                .padding(.top, 1)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(Sky.semibold(15)).foregroundColor(Sky.ink)
                    if let detail { Text(detail).font(Sky.body(12.5)).foregroundColor(Sky.muted(0.6)) }
                }
                Spacer()
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Back link + big title + optional description; the top of every pushed screen.
struct ScreenHeader: View {
    let back: LocalizedStringKey
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    let onBack: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BackButton(title: back, action: onBack).padding(.bottom, 16)
            Text(title).font(Sky.heading(28)).foregroundColor(Sky.ink)
            if let subtitle {
                Text(subtitle).font(Sky.body(14)).foregroundColor(Sky.muted(0.65)).padding(.top, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 20).leading()
        .overlay(Rule(), alignment: .bottom)
    }
}


/// Marketing/demo navigation: `-DemoMode YES -DemoScreen <servers|chooser|paste|added|settings>`
/// opens a screen directly so App Store screenshots can be captured without taps.
enum DemoRouter {
    static var screen: String? { UserDefaults.standard.bool(forKey: "DemoMode") ? UserDefaults.standard.string(forKey: "DemoScreen") : nil }
    static let sampleLink = "vless://8f3c1a2e-77b4-4d19-9c02-5aa1e6b3f0d7@de1.skyray.app:443?encryption=none&security=reality&sni=www.apple.com&fp=chrome&pbk=SbVKOEMjK0sIlbwg4akyBg5mL5KZwwB-ed4eEE7YnRc&sid=6ba85179e30d4fc2&type=tcp&flow=xtls-rprx-vision#Frankfurt%20%C2%B7%20Reality"
}
