import Foundation

struct MomentPost: Codable, Identifiable, Hashable {
    let id: Int
    let author_id: Int
    let author_name: String
    let author_initials: String
    var author_avatar_url: String?
    var author_city: String?
    let content: String
    let image_url: String?
    var location: String?
    let created_at: String
    var like_count: Int
    var liked: Bool
    var comment_count: Int

    var shortTime: String {
        let parts = created_at.split(separator: "T")
        if parts.count == 2 { return "\(parts[0]) \(parts[1].prefix(5))" }
        return created_at
    }

    /// 微信式相对发布时间：刚刚 / X分钟前 / X小时前 / 昨天 / X天前 / 月-日。
    var displayTime: String { RelativeTime.string(fromISO: created_at) }
}

/// 把后端 UTC 的 ISO8601 时间转成中文相对时间。
enum RelativeTime {
    static func string(fromISO iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = f.date(from: iso)
        if date == nil {
            f.formatOptions = [.withInternetDateTime]
            date = f.date(from: iso)
        }
        if date == nil {
            // 后端多为不带时区的 UTC（如 2026-06-28T12:34:56），按 UTC 解析
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(identifier: "UTC")
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            date = df.date(from: String(iso.prefix(19)))
        }
        guard let d = date else { return iso }
        let s = max(0, Date().timeIntervalSince(d))
        if s < 60 { return "刚刚" }
        if s < 3600 { return "\(Int(s / 60))分钟前" }
        if s < 86400 { return "\(Int(s / 3600))小时前" }
        let days = Int(s / 86400)
        if days == 1 { return "昨天" }
        if days < 7 { return "\(days)天前" }
        let out = DateFormatter()
        out.locale = Locale(identifier: "zh_CN")
        out.dateFormat = "M月d日"
        return out.string(from: d)
    }
}

struct PostDetailDTO: Codable, Hashable {
    let post: MomentPost
    let comments: [MomentComment]
}

struct MomentComment: Codable, Identifiable, Hashable {
    let id: Int
    let user_name: String
    let initials: String
    let content: String
    let created_at: String
}

struct LikeResult: Codable { let liked: Bool; let like_count: Int }
