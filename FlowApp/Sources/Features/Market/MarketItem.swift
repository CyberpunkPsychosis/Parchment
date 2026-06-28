import SwiftUI

/// 认领市场里的一个已发布搭子快照。
struct MarketItem: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let persona: String
    let avatar: String
    let tint: String
    let greeting: String
    let publisher_name: String
    let lineage_depth: Int
    let adopt_count: Int
    let memory_count: Int
    let is_mine: Bool
    var memories: [String]? = nil   // 仅详情接口返回（预览前几条）
    var hidden_count: Int? = nil    // 还有多少条认领后才能发现

    var tintColor: Color {
        switch tint {
        case "sage": return FlowTheme.sage
        case "ink": return FlowTheme.ink
        case "tealDark": return FlowTheme.tealDark
        case "gray": return FlowTheme.gray
        default: return FlowTheme.teal
        }
    }
}
