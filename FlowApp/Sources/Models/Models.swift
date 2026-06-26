import SwiftUI

struct Contact: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let initials: String
    let tint: Color
}

struct ChatSummary: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let initials: String
    let tint: Color
    let preview: String
    let time: String
    let unread: Int
    let isGroup: Bool
}

enum MessageKind: Hashable {
    case text(String)
    case image          // uses a sketch placeholder
    case voice(seconds: Int)
}

struct Message: Identifiable, Hashable {
    let id = UUID()
    let kind: MessageKind
    let mine: Bool
    let time: String
}

struct EliteService: Identifiable, Hashable {
    let id = UUID()
    let titleZh: String
    let titleEn: String
    let subtitleZh: String
    let subtitleEn: String
    let image: String      // asset name
    let members: String
}
