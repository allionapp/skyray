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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Sky.heading(15))
            .foregroundColor(foreground)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
            .padding(.horizontal, 18)
            .background(fill.opacity(configuration.isPressed ? 0.8 : 1))
            .contentShape(Rectangle())
    }
}

/// Outlined action, label flush left.
struct SecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 54
    var onField = false
    var fullWidth = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Sky.heading(fullWidth ? 15 : 13))
            .foregroundColor(onField ? Sky.onField : Sky.ink)
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


/// Marketing/demo navigation: `-DemoMode YES -DemoScreen <servers|chooser|paste|added>`
/// opens a screen directly so App Store screenshots can be captured without taps.
enum DemoRouter {
    static var screen: String? { UserDefaults.standard.bool(forKey: "DemoMode") ? UserDefaults.standard.string(forKey: "DemoScreen") : nil }
    static let sampleLink = "vless://8f3c1a2e-77b4-4d19-9c02-5aa1e6b3f0d7@de1.skyray.app:443?encryption=none&security=reality&sni=www.apple.com&fp=chrome&pbk=SbVKOEMjK0sIlbwg4akyBg5mL5KZwwB-ed4eEE7YnRc&sid=6ba85179e30d4fc2&type=tcp&flow=xtls-rprx-vision#Frankfurt%20%C2%B7%20Reality"
}
