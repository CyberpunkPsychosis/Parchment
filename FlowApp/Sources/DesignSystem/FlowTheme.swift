import SwiftUI
import UIKit

/// Palette + typography。颜色用「动态色」实现：根据当前明暗 trait 自动解析浅/深值，
/// 系统或 .preferredColorScheme 切换时由 SwiftUI 原生重渲染，不会残留。
enum FlowTheme {
    private static func uic(_ hex: UInt) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
    /// 浅色值 / 深色值 → 动态 Color
    private static func dyn(_ light: UInt, _ dark: UInt) -> Color {
        Color(UIColor { tc in tc.userInterfaceStyle == .dark ? uic(dark) : uic(light) })
    }
    private static func dynA(_ light: UInt, _ dark: UInt, _ a: CGFloat) -> Color {
        Color(UIColor { tc in (tc.userInterfaceStyle == .dark ? uic(dark) : uic(light)).withAlphaComponent(a) })
    }

    // Core palette（浅色值，深色值）
    static var ink: Color       { dyn(0x2F3E46, 0xEDE8DC) } // 主文字
    static var line: Color      { dyn(0x3D4C54, 0x6E7C74) } // 手绘描边
    static var teal: Color      { dyn(0x4A7C81, 0x6FB1B0) } // 主色
    static var tealDark: Color  { dyn(0x3C666A, 0x4A7C81) }
    static var sage: Color      { dyn(0x86A892, 0x4E6B58) } // 发出气泡
    static var sageInk: Color   { dyn(0x22312B, 0xEAF2EC) } // 发出气泡文字
    static var parchment: Color { dyn(0xF3EDE2, 0x1B201B) } // app 背景
    static var card: Color      { dyn(0xFCFAF4, 0x2A302A) } // 卡片
    static var beige: Color     { dyn(0xE7E1D4, 0x39403A) } // 输入框
    static var gray: Color      { dyn(0x8C8F93, 0x9DA29C) } // 次要文字
    static var online: Color    { dyn(0x5FA776, 0x6FB880) }
    static var field: Color     { dyn(0xFDFCF7, 0x2E342E) } // 输入框 / 浅底
    static var chatBg: Color    { dyn(0xDFE3E2, 0x161A16) } // 聊天背景

    static var stroke: Color    { dynA(0x2F3E46, 0xEDE8DC, 0.10) }
    static var shadow: Color    { Color.black.opacity(0.12) }

    // Typography
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
