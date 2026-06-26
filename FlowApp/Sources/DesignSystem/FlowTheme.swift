import SwiftUI

/// Palette + typography extracted 1:1 from the FLOW design system sheet.
/// Hex values sampled directly from the design (`#4A7C81`, `#F5F1EA`, …).
enum FlowTheme {
    // Core palette
    static let ink       = Color(hex: 0x2F3E46) // deep slate – primary text / dark surfaces
    static let line      = Color(hex: 0x3D4C54) // hand-drawn sketch border
    static let teal      = Color(hex: 0x4A7C81) // primary action
    static let tealDark  = Color(hex: 0x3C666A) // pressed / deep teal
    static let sage      = Color(hex: 0x86A892) // sent bubbles
    static let sageInk   = Color(hex: 0x22312B) // text on sent bubbles
    static let parchment = Color(hex: 0xF3EDE2) // app background
    static let card      = Color(hex: 0xFCFAF4) // raised cards
    static let beige     = Color(hex: 0xE7E1D4) // fields
    static let gray      = Color(hex: 0x8C8F93) // secondary text / icons
    static let online    = Color(hex: 0x5FA776) // online dot

    static let stroke    = Color(hex: 0x2F3E46).opacity(0.10)
    static let shadow    = Color(hex: 0x2F3E46).opacity(0.12)

    // Typography – serif display + sans body, per the spec sheet
    static func title(_ size: CGFloat = 28) -> Font { .system(size: size, weight: .semibold, design: .serif) }
    static func heading(_ size: CGFloat = 20) -> Font { .system(size: size, weight: .semibold, design: .serif) }
    static func body(_ size: CGFloat = 16) -> Font { .system(size: size, weight: .regular) }
    static func caption(_ size: CGFloat = 12) -> Font { .system(size: size, weight: .regular) }

    static let cornerCard: CGFloat = 22
    static let cornerField: CGFloat = 16
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
