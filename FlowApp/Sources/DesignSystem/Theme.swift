import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var key: String { "appearance.\(rawValue)" }
}

/// 外观控制：跟随系统 / 浅色 / 深色。通过 .preferredColorScheme 生效，
/// FlowTheme 的动态色据此自动解析。
final class Theme: ObservableObject {
    @Published var mode: AppearanceMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "flow.appearance") }
    }

    init() {
        mode = AppearanceMode(rawValue: UserDefaults.standard.string(forKey: "flow.appearance") ?? "system") ?? .system
    }

    var preferredScheme: ColorScheme? {
        switch mode {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}
