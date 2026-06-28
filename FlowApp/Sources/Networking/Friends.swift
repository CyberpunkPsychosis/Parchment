import SwiftUI

struct FriendUser: Codable, Identifiable, Hashable {
    let id: Int
    let nickname: String
    let initials: String
    let tint: String
    var avatar_url: String? = nil
    var bio: String? = nil
    var is_friend: Bool
    var outgoing_pending: Bool
    var incoming_pending: Bool
    var is_me: Bool
    var companions: [Companion]? = nil

    var tintColor: Color { FlowTheme.tint(tint) }
}

struct BlockedUser: Codable, Identifiable, Hashable {
    let user_id: Int
    let nickname: String
    var avatar_url: String? = nil
    var id: Int { user_id }
    var initials: String { nickname.prefix(2).uppercased() }
}

struct IncomingRequest: Codable, Identifiable, Hashable {
    let id: Int
    let from_user_id: Int
    let nickname: String
    let initials: String
    let tint: String
    var avatar_url: String? = nil

    var tintColor: Color { FlowTheme.tint(tint) }
}
