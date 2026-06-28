import SwiftUI

/// 广场里的群组。
struct PlazaGroup: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let description: String
    let avatar: String
    let tint: String
    let join_mode: String       // open | code | approval
    let member_cap: Int
    let member_count: Int
    let owner_name: String
    var is_member: Bool
    var pending: Bool
    let is_owner: Bool
    var invite_code: String?

    var members: [GroupMemberDTO]? = nil   // 仅详情接口返回

    var tintColor: Color {
        switch tint {
        case "sage": return FlowTheme.sage
        case "ink": return FlowTheme.ink
        case "tealDark": return FlowTheme.tealDark
        case "gray": return FlowTheme.gray
        default: return FlowTheme.teal
        }
    }
    var modeKey: String { "group.mode.\(join_mode)" }
}

struct GroupMemberDTO: Codable, Hashable {
    let name: String
    let initials: String
    let is_owner: Bool
}
