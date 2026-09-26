import SwiftUI

/// The look SkyRay shares with its Android build (a v2rayNG-based client): a quiet grey canvas,
/// white rounded cards, one blue for every action and green for a live connection, set in the
/// system typeface. The Modernist `Sky` theme still dresses the advanced screens.
enum Etha {
    static let brand = Color(hex: 0x1D4ED8)
    static let live = Color(hex: 0x009966)
    static let canvas = Color("EthaCanvas", bundle: nil, light: 0xF3F4F8, dark: 0x0F1115)
    static let card = Color("EthaCard", bundle: nil, light: 0xFFFFFF, dark: 0x1B1E25)
    static let tile = Color("EthaTile", bundle: nil, light: 0xEEF2FF, dark: 0x242A38)
    static let ink = Color("EthaInk", bundle: nil, light: 0x111827, dark: 0xF3F4F6)
    static let muted = Color("EthaMuted", bundle: nil, light: 0x6B7280, dark: 0x9CA3AF)
    static let outline = Color("EthaOutline", bundle: nil, light: 0x6B7280, dark: 0x6B7280)
}

/// A white, generously rounded card, the one container the new screens are built from.
struct EthaCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(22)
            .frame(maxWidth: .infinity)
            .background(Etha.card)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

/// The filled, pill-shaped primary button.
struct EthaFilledButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .medium))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Etha.brand.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(Capsule())
    }
}

/// The outlined, pill-shaped secondary button.
struct EthaOutlinedButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .medium))
            .foregroundColor(Etha.brand)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Etha.card.opacity(configuration.isPressed ? 0.6 : 1))
            .overlay(Capsule().stroke(Etha.outline.opacity(0.6), lineWidth: 1.2))
            .clipShape(Capsule())
    }
}
