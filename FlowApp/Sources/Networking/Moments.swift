import Foundation

struct MomentPost: Codable, Identifiable, Hashable {
    let id: Int
    let author_id: Int
    let author_name: String
    let author_initials: String
    var author_avatar_url: String?
    let content: String
    let image_url: String?
    let created_at: String
    var like_count: Int
    var liked: Bool
    let comment_count: Int

    var shortTime: String {
        let parts = created_at.split(separator: "T")
        if parts.count == 2 { return "\(parts[0]) \(parts[1].prefix(5))" }
        return created_at
    }
}

struct MomentComment: Codable, Identifiable, Hashable {
    let id: Int
    let user_name: String
    let initials: String
    let content: String
    let created_at: String
}

struct LikeResult: Codable { let liked: Bool; let like_count: Int }
