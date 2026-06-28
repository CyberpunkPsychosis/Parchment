import SwiftUI

/// AI 搭子（后端模型）。
struct Companion: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let persona: String
    let avatar: String
    let tint: String
    let greeting: String
    var visibility: String = "private"
    var memory_count: Int = 0
    // —— 成长系统 ——
    var exp: Int = 0
    var level: Int = 1
    var stage: String = "幼年"
    var level_min_exp: Int = 0
    var level_max_exp: Int = 50

    var tintColor: Color {
        switch tint {
        case "sage": return FlowTheme.sage
        case "ink": return FlowTheme.ink
        case "tealDark": return FlowTheme.tealDark
        case "gray": return FlowTheme.gray
        default: return FlowTheme.teal
        }
    }

    /// 当前等级内的经验进度 0~1。
    var levelProgress: Double {
        let span = max(1, level_max_exp - level_min_exp)
        return min(1, max(0, Double(exp - level_min_exp) / Double(span)))
    }

    /// 给 ChatDetailView 复用的会话头信息。
    var asChat: ChatSummary {
        ChatSummary(name: name, initials: avatar, tint: tintColor,
                    preview: "", time: "", unread: 0, isGroup: false)
    }
}

/// 搭子记忆。
struct Memory: Codable, Identifiable, Hashable {
    let id: Int
    let content: String
    let source: String      // auto | manual | inherited
    let visibility: String
    var origin: String?     // 来自哪位前任主人（nil=自己的）
    let created_at: String
}

/// 可选的头像配色（创建搭子时用）。
enum CompanionTint: String, CaseIterable, Identifiable {
    case teal, sage, tealDark, ink, gray
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .teal: return FlowTheme.teal
        case .sage: return FlowTheme.sage
        case .tealDark: return FlowTheme.tealDark
        case .ink: return FlowTheme.ink
        case .gray: return FlowTheme.gray
        }
    }
}
