import SwiftUI

struct FriendUser: Codable, Identifiable, Hashable {
    let id: Int
    let nickname: String
    let initials: String
    let tint: String
    var is_friend: Bool
    var outgoing_pending: Bool
    var incoming_pending: Bool
    var is_me: Bool
    var companions: [Companion]? = nil

    var tintColor: Color { FlowTheme.tint(tint) }
}

struct IncomingRequest: Codable, Identifiable, Hashable {
    let id: Int
    let from_user_id: Int
    let nickname: String
    let initials: String
    let tint: String

    var tintColor: Color { FlowTheme.tint(tint) }
}
