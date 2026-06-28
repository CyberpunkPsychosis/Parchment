import SwiftUI

struct SearchUser: Codable, Identifiable, Hashable {
    let id: Int
    let nickname: String
    let initials: String
    let tint: String
    var avatar_url: String?
    var tintColor: Color { FlowTheme.tint(tint) }
}

struct SearchGroup: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let avatar: String
    let tint: String
    let member_count: Int
    var member_cap: Int?
    let is_member: Bool
    var tintColor: Color { FlowTheme.tint(tint) }
}

struct SearchCompanion: Codable, Identifiable, Hashable {
    let snapshot_id: Int
    let name: String
    let avatar: String
    let tint: String
    let persona: String
    let publisher_name: String
    var id: Int { snapshot_id }
    var tintColor: Color { FlowTheme.tint(tint) }
}

struct SearchResults: Codable {
    var users: [SearchUser] = []
    var groups: [SearchGroup] = []
    var companions: [SearchCompanion] = []
}
